"""FPGA-side simulator: plays the FPGA role of protocol V1 over UDP.

Packets are written straight into the output file at their computed DDR
offset (Slice_ID * 262144 + Packet_Idx * 1024, relative to Image_Base_Addr),
exactly like the real FPGA writes into DDR, so a partially received volume
reads back with zero holes. Optional drop_rate randomly discards IMAGE_DATA
frames to exercise the sender's retransmission path.
"""

from dataclasses import dataclass
from pathlib import Path
from random import Random
from time import monotonic
import zlib

import numpy as np

from src.protocol import (
    ACK_ACCEPTED,
    ACK_INVALID_PARAMETER,
    BATCH_COMPLETE,
    BATCH_CRC_ERROR,
    BATCH_MISSING,
    BATCH_PARAM_ERROR,
    Frame,
    FrameError,
    ImageBegin,
    PACKET_PIXEL_BYTES,
    PACKETS_PER_SLICE,
    READY_CRC_ERROR,
    READY_DDR_ERROR,
    READY_MISSING,
    READY_OK,
    READY_PARAM_MISMATCH,
    SLICE_BYTES,
    MSG_ACK,
    MSG_BATCH_END,
    MSG_BATCH_STATUS,
    MSG_IMAGE_BEGIN,
    MSG_IMAGE_DATA,
    MSG_IMAGE_END,
    MSG_IMAGE_READY,
    MSG_INFER_DONE,
    MSG_INFER_TRIGGER,
    MSG_TRANSFER_ABORT,
    INFER_OK,
    INFER_NOT_READY,
    INFER_PARAM_ERROR,
    INFER_RESULT_DUMMY,
    build_ack_body,
    build_batch_status_body,
    build_frame,
    build_image_ready_body,
    build_infer_done_body,
    check_fpga_requirements,
    missing_to_bitmap,
    parse_batch_end_body,
    parse_image_begin,
    parse_image_data_body,
    parse_image_end_body,
    parse_frame,
    parse_infer_trigger_body,
)
from src.udp_link import UdpPeer

PROGRESS_EVERY_BATCHES = 25


class _ReceiveContext:
    """State of one Transfer_ID: parameters, packet bitmap and the DDR file."""

    def __init__(self, params: ImageBegin, out_path: Path) -> None:
        self.params = params
        self.path = out_path
        self.bitmap = bytearray(params.expected_packets)  # 0 missing, 1 received
        self.file = out_path.open("wb+")
        self.file.truncate(params.total_bytes)
        self.received_packets = 0
        self.duplicates = 0
        self.bad_packets = 0
        self.ready_status: int | None = None
        self.calculated_crc32: int | None = None

    def close(self) -> None:
        if not self.file.closed:
            self.file.flush()
            self.file.close()

    def received_slices(self) -> int:
        pps = self.params.packets_per_slice
        return sum(
            1
            for z in range(self.params.total_slices)
            if all(self.bitmap[z * pps + i] for i in range(pps))
        )

    def crc32_range(self, start: int, length: int) -> int:
        crc = 0
        self.file.seek(start)
        remaining = length
        while remaining > 0:
            chunk = self.file.read(min(4 * 1024 * 1024, remaining))
            if not chunk:
                break
            crc = zlib.crc32(chunk, crc)
            remaining -= len(chunk)
        return crc & 0xFFFFFFFF


@dataclass
class SimulatorConfig:
    drop_rate: float = 0.0     # simulated RX loss on IMAGE_DATA only
    drop_seed: int = 1
    idle_timeout: float = 10.0


class FpgaSimulator:
    def __init__(self, link: UdpPeer, out_path: Path,
                 config: SimulatorConfig | None = None) -> None:
        self.link = link
        self.out_path = out_path
        self.config = config or SimulatorConfig()
        self.counters = {
            "rx_image_data": 0,
            "rx_image_begin": 0,
            "rx_batch_end": 0,
            "rx_image_end": 0,
            "rx_infer_trigger": 0,
            "rx_transfer_abort": 0,
            "rx_stray": 0,
            "rx_bad_frames": 0,
            "rx_bad_body": 0,
            "dropped_simulated": 0,
            "duplicates": 0,
            "batches_complete": 0,
            "batches_missing": 0,
            "batches_crc_error": 0,
        }
        self.report: dict = {}
        self._ctx: _ReceiveContext | None = None
        self._transfer_id: int | None = None
        self._reply_seq = 0
        self._rng = Random(self.config.drop_seed)
        self._last_rx: float | None = None
        self._done = False
        self._patch_info: dict | None = None

    # --- main loop -----------------------------------------------------------

    def run(self) -> dict:
        started = monotonic()
        print(f"[recv] FPGA simulator on {self.link.local_addr}, "
              f"output {self.out_path}, drop_rate {self.config.drop_rate}",
              flush=True)
        try:
            while True:
                packet = self.link.recvfrom(0.5)
                now = monotonic()
                if packet is None:
                    if (self._last_rx is not None
                            and now - self._last_rx > self.config.idle_timeout):
                        print(f"[recv] idle for {self.config.idle_timeout:.0f}s "
                              "after last traffic, stopping", flush=True)
                        break
                    continue
                data, addr = packet
                self._last_rx = now
                # Simulated RX loss applies to IMAGE_DATA only (byte 3 = Msg_Type).
                # Pure random drop per packet arrival - no retransmission privilege.
                if (len(data) > 3 and data[3] == MSG_IMAGE_DATA
                        and self._rng.random() < self.config.drop_rate):
                    self.counters["dropped_simulated"] += 1
                    continue
                try:
                    frame = parse_frame(data)
                except FrameError:
                    self.counters["rx_bad_frames"] += 1
                    continue
                reply = self._dispatch(frame)
                if reply is not None:
                    self.link.sendto(reply, addr)
                if self._done:
                    break
        except KeyboardInterrupt:
            print("[recv] interrupted by user", flush=True)
        finally:
            if self._ctx is not None:
                self._ctx.close()
        self._build_report(monotonic() - started)
        return self.report

    # --- dispatch ------------------------------------------------------------

    def _dispatch(self, frame: Frame) -> bytes | None:
        if frame.msg_type == MSG_IMAGE_BEGIN:
            return self._on_image_begin(frame)
        if frame.msg_type == MSG_IMAGE_DATA:
            return self._on_image_data(frame)
        if frame.msg_type == MSG_BATCH_END:
            return self._on_batch_end(frame)
        if frame.msg_type == MSG_IMAGE_END:
            return self._on_image_end(frame)
        if frame.msg_type == MSG_INFER_TRIGGER:
            return self._on_infer_trigger(frame)
        if frame.msg_type == MSG_TRANSFER_ABORT:
            self.counters["rx_transfer_abort"] += 1
            print(f"[recv] TRANSFER_ABORT for transfer {frame.transfer_id}, "
                  "context dropped", flush=True)
            self._reset_context()
            return None
        self.counters["rx_stray"] += 1
        return None

    def _reply(self, msg_type: int, body: bytes) -> bytes:
        frame = build_frame(msg_type, self._transfer_id or 0,
                            self._reply_seq, body)
        self._reply_seq += 1
        return frame

    def _reset_context(self) -> None:
        if self._ctx is not None:
            self._ctx.close()
        self._ctx = None
        self._transfer_id = None

    # --- handlers ------------------------------------------------------------

    def _on_image_begin(self, frame: Frame) -> bytes:
        self.counters["rx_image_begin"] += 1
        try:
            begin = parse_image_begin(frame.body)
        except FrameError:
            self.counters["rx_bad_body"] += 1
            return self._reply(MSG_ACK, build_ack_body(
                MSG_IMAGE_BEGIN, ACK_INVALID_PARAMETER, 0x00FF, frame.sequence))

        problem = check_fpga_requirements(begin)
        if problem is not None:
            print(f"[recv] IMAGE_BEGIN rejected: {problem}", flush=True)
            return self._reply(MSG_ACK, build_ack_body(
                MSG_IMAGE_BEGIN, ACK_INVALID_PARAMETER, 0x0001, frame.sequence))

        if self._ctx is not None and frame.transfer_id == self._transfer_id:
            # Duplicate IMAGE_BEGIN (our ACK was lost): keep the bitmap intact.
            print("[recv] duplicate IMAGE_BEGIN, re-acking", flush=True)
        else:
            if self._ctx is not None:
                print(f"[recv] warning: transfer {self._transfer_id} replaced by "
                      f"{frame.transfer_id} before completion", flush=True)
                self._reset_context()
            self._transfer_id = frame.transfer_id
            self._ctx = _ReceiveContext(begin, self.out_path)
            print(f"[recv] IMAGE_BEGIN accepted: transfer 0x{frame.transfer_id:08X}, "
                  f"{begin.total_slices} slices, {begin.total_bytes:,} bytes, "
                  f"batch {begin.batch_slices} slice(s), "
                  f"DDR base 0x{begin.image_base_addr:X}", flush=True)
        return self._reply(MSG_ACK, build_ack_body(
            MSG_IMAGE_BEGIN, ACK_ACCEPTED, 0, frame.sequence))

    def _on_image_data(self, frame: Frame) -> bytes | None:
        if self._ctx is None or frame.transfer_id != self._transfer_id:
            self.counters["rx_stray"] += 1
            return None
        self.counters["rx_image_data"] += 1
        try:
            slice_id, packet_idx, pixel_len, pixels = parse_image_data_body(frame.body)
        except FrameError:
            self.counters["rx_bad_body"] += 1
            return None
        params = self._ctx.params
        if (pixel_len != PACKET_PIXEL_BYTES
                or not 0 <= slice_id < params.total_slices
                or not 0 <= packet_idx < params.packets_per_slice):
            self._ctx.bad_packets += 1
            return None

        bit = slice_id * params.packets_per_slice + packet_idx
        if self._ctx.bitmap[bit]:
            self._ctx.duplicates += 1
            self.counters["duplicates"] += 1
            return None
        offset = slice_id * params.slice_stride_bytes + packet_idx * PACKET_PIXEL_BYTES
        self._ctx.file.seek(offset)
        self._ctx.file.write(pixels)
        self._ctx.bitmap[bit] = 1
        self._ctx.received_packets += 1
        return None

    def _on_batch_end(self, frame: Frame) -> bytes | None:
        if self._ctx is None or frame.transfer_id != self._transfer_id:
            self.counters["rx_stray"] += 1
            return None
        self.counters["rx_batch_end"] += 1
        try:
            batch_id, first_slice, slice_count, expected, batch_crc = (
                parse_batch_end_body(frame.body)
            )
        except FrameError:
            self.counters["rx_bad_body"] += 1
            return None
        params = self._ctx.params
        if (slice_count < 1 or first_slice < 0
                or first_slice + slice_count > params.total_slices
                or expected != slice_count * params.packets_per_slice):
            return self._reply(MSG_BATCH_STATUS, build_batch_status_body(
                batch_id, BATCH_PARAM_ERROR, expected, 0, None))

        packets_expected = slice_count * params.packets_per_slice
        base_bit = first_slice * params.packets_per_slice
        missing = [i for i in range(packets_expected)
                   if not self._ctx.bitmap[base_bit + i]]
        if missing:
            status = BATCH_MISSING
            self.counters["batches_missing"] += 1
            print(f"[recv] batch {batch_id} slices {first_slice}.."
                  f"{first_slice + slice_count - 1}: missing "
                  f"{len(missing)}/{packets_expected} packets", flush=True)
        else:
            calculated = self._ctx.crc32_range(
                first_slice * params.slice_stride_bytes,
                slice_count * params.slice_stride_bytes,
            )
            if calculated == batch_crc:
                status = BATCH_COMPLETE
                self.counters["batches_complete"] += 1
            else:
                status = BATCH_CRC_ERROR
                self.counters["batches_crc_error"] += 1
                print(f"[recv] batch {batch_id}: CRC mismatch "
                      f"0x{calculated:08X} != 0x{batch_crc:08X}", flush=True)
            done = first_slice + slice_count
            if done % (PROGRESS_EVERY_BATCHES * max(params.batch_slices, 1)) < slice_count:
                print(f"[recv] progress: {done}/{params.total_slices} slices "
                      f"verified, {self._ctx.received_packets} packets, "
                      f"{self._ctx.duplicates} duplicates", flush=True)
        bitmap = missing_to_bitmap(missing, packets_expected)
        return self._reply(MSG_BATCH_STATUS, build_batch_status_body(
            batch_id, status, packets_expected,
            packets_expected - len(missing), bitmap))

    def _on_image_end(self, frame: Frame) -> bytes | None:
        if self._ctx is None or frame.transfer_id != self._transfer_id:
            self.counters["rx_stray"] += 1
            return None
        self.counters["rx_image_end"] += 1
        try:
            expected_packets, expected_bytes, whole_crc, _flags = (
                parse_image_end_body(frame.body)
            )
        except FrameError:
            self.counters["rx_bad_body"] += 1
            return None
        params = self._ctx.params
        missing_total = self._ctx.bitmap.count(0)
        received_slices = self._ctx.received_slices()
        calculated = self._ctx.crc32_range(0, params.total_bytes)
        self._ctx.calculated_crc32 = calculated

        if (expected_packets != params.expected_packets
                or expected_bytes != params.total_bytes):
            status = READY_PARAM_MISMATCH
        elif missing_total:
            status = READY_MISSING
        elif whole_crc and calculated != whole_crc:
            status = READY_CRC_ERROR
        else:
            status = READY_OK
        self._ctx.ready_status = status

        names = {READY_OK: "OK", READY_MISSING: "MISSING_PACKETS",
                 READY_CRC_ERROR: "CRC_ERROR", READY_PARAM_MISMATCH: "PARAM_MISMATCH",
                 READY_DDR_ERROR: "DDR_ERROR"}
        print(f"[recv] IMAGE_END check: {self._ctx.received_packets}/"
              f"{params.expected_packets} packets, {received_slices}/"
              f"{params.total_slices} slices, CRC 0x{calculated:08X} "
              f"(expected 0x{whole_crc:08X}) -> {names.get(status, hex(status))}",
              flush=True)
        return self._reply(MSG_IMAGE_READY, build_image_ready_body(
            status, received_slices, self._ctx.received_packets,
            self._ctx.received_packets * PACKET_PIXEL_BYTES,
            calculated, params.image_base_addr))

    def _on_infer_trigger(self, frame: Frame) -> bytes:
        self.counters["rx_infer_trigger"] += 1
        try:
            trigger = parse_infer_trigger_body(frame.body)
        except FrameError:
            self.counters["rx_bad_body"] += 1
            return self._reply(MSG_INFER_DONE, build_infer_done_body(
                0, 0, INFER_PARAM_ERROR))
        if self._ctx is None or self._transfer_id != frame.transfer_id:
            return self._reply(MSG_INFER_DONE, build_infer_done_body(
                trigger.task_id, trigger.center_slice_id, INFER_NOT_READY))
        params = self._ctx.params
        if self._ctx.ready_status != READY_OK:
            return self._reply(MSG_INFER_DONE, build_infer_done_body(
                trigger.task_id, trigger.center_slice_id, INFER_NOT_READY))
        valid = (
            trigger.depth == params.depth
            and trigger.center_index == params.center_index
            and trigger.patch_size == params.patch_size
            and 0 <= trigger.center_slice_id < params.total_slices
            and 0 <= trigger.patch_start_y < params.height
            and 0 <= trigger.patch_start_x < params.width
        )
        if not valid:
            return self._reply(MSG_INFER_DONE, build_infer_done_body(
                trigger.task_id, trigger.center_slice_id, INFER_PARAM_ERROR))

        patch_info = self._extract_patch(trigger)
        print(f"[recv] INFER_TRIGGER task 0x{trigger.task_id:08X}: center "
              f"{trigger.center_slice_id}, patch y={trigger.patch_start_y} "
              f"x={trigger.patch_start_x} -> source_z "
              f"{patch_info['source_z_first']}..{patch_info['source_z_last']}, "
              f"patch CRC32 0x{patch_info['patch_crc32']:08X}", flush=True)
        self._done = True
        return self._reply(MSG_INFER_DONE, build_infer_done_body(
            trigger.task_id, trigger.center_slice_id, INFER_OK,
            result_value=INFER_RESULT_DUMMY))

    def _extract_patch(self, trigger) -> dict:
        """Build the [1,1,33,96,96] input per doc §14/§15 from the DDR file."""
        params = self._ctx.params
        self._ctx.file.flush()
        volume = np.memmap(self._ctx.path, dtype=np.int8, mode="r")
        volume = volume.reshape(params.total_slices, params.height, params.width)
        # Z: repeat boundary, source_z = clip(center + d - 16, 0, N-1)
        source_z = np.clip(
            trigger.center_slice_id + np.arange(params.depth) - params.center_index,
            0, params.total_slices - 1)
        # XY: edge padding, source = clip(start + i, 0, 511)
        rows = np.clip(trigger.patch_start_y + np.arange(params.patch_size),
                       0, params.height - 1)
        cols = np.clip(trigger.patch_start_x + np.arange(params.patch_size),
                       0, params.width - 1)
        patch = np.ascontiguousarray(volume[np.ix_(source_z, rows, cols)])
        self._patch_info = {
            "task_id": trigger.task_id,
            "center_slice_id": trigger.center_slice_id,
            "patch_start_y": trigger.patch_start_y,
            "patch_start_x": trigger.patch_start_x,
            "shape": [1, 1, *patch.shape],
            "source_z_first": int(source_z[0]),
            "source_z_last": int(source_z[-1]),
            "patch_crc32": zlib.crc32(patch.tobytes()) & 0xFFFFFFFF,
            "result_dummy": f"0x{INFER_RESULT_DUMMY:08X}",
        }
        return self._patch_info

    # --- report ----------------------------------------------------------------

    def _build_report(self, duration_s: float) -> None:
        ctx = self._ctx
        self.report = {
            "duration_s": duration_s,
            "output_file": str(self.out_path),
            "transfer_id": self._transfer_id,
            "counters": dict(self.counters),
            "ready_status": ctx.ready_status if ctx else None,
            "calculated_crc32": ctx.calculated_crc32 if ctx else None,
            "received_packets": ctx.received_packets if ctx else 0,
            "received_slices": ctx.received_slices() if ctx else 0,
            "duplicates": ctx.duplicates if ctx else 0,
            "params": {
                "total_slices": ctx.params.total_slices,
                "total_bytes": ctx.params.total_bytes,
                "expected_packets": ctx.params.expected_packets,
                "batch_slices": ctx.params.batch_slices,
                "image_base_addr": ctx.params.image_base_addr,
            } if ctx else None,
            "patch_info": self._patch_info,
        }
