"""PC-side sender: one logical volume transfer per protocol V1 (doc §18).

Sequence convention (doc §5.2): IMAGE_BEGIN uses Sequence 0; every newly
emitted frame increments it; a retransmitted IMAGE_DATA reuses its original
frame bytes, hence its original Sequence. BATCH_END re-sends get a fresh
Sequence because each one is a new emission that must trigger a fresh
BATCH_STATUS (the receiver never deduplicates control frames by Sequence).
"""

from dataclasses import dataclass
from pathlib import Path
from time import monotonic, sleep
import zlib

from .protocol import (
    ACK_ACCEPTED,
    ACK_STATUSES,
    BATCH_COMPLETE,
    BATCH_MISSING,
    Frame,
    FrameError,
    ImageBegin,
    InferTrigger,
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
    PACKETS_PER_SLICE,
    PACKET_PIXEL_BYTES,
    READY_OK,
    READY_DDR_ERROR,
    SLICE_BYTES,
    build_batch_end_body,
    build_frame,
    build_image_data_body,
    build_image_end_body,
    build_infer_trigger_body,
    parse_ack_body,
    parse_batch_status_body,
    parse_frame,
    parse_image_ready_body,
    parse_infer_done_body,
    bitmap_to_missing,
)
from .udp_link import UdpPeer

PROGRESS_EVERY_BATCHES = 25


class TransferError(RuntimeError):
    """A transfer-stage failure that should abort the current Transfer_ID."""


@dataclass
class SenderConfig:
    begin_timeout: float = 1.0      # doc §19: IMAGE_BEGIN ACK timeout 1 s
    begin_retries: int = 5
    status_timeout: float = 0.5     # doc §19: BATCH_STATUS timeout 500 ms
    max_batch_attempts: int = 4     # 1 initial + 3 retransmits (doc §19)
    ready_timeout: float = 2.0
    ready_retries: int = 3
    pace_us: int = 0                # optional: sleep every pace_every packets
    pace_every: int = 32


class VolumeSender:
    def __init__(self, link: UdpPeer, peer: tuple[str, int], bin_path: Path,
                 params: ImageBegin, transfer_id: int,
                 config: SenderConfig | None = None, log=None) -> None:
        self.link = link
        self.peer = peer
        self.bin_path = bin_path
        self.params = params
        self.transfer_id = transfer_id
        self.config = config or SenderConfig()        self.log = log or (lambda *args, **kwargs: None)
        self._next_seq = 0
        self._file = None
        self.stats: dict = {}

    # --- sequence / low-level helpers -------------------------------------

    def _alloc_seq(self) -> int:
        sequence = self._next_seq
        self._next_seq += 1
        return sequence

    def _send(self, frame_bytes: bytes) -> None:
        try:
            self.link.sendto(frame_bytes, self.peer)
        except OSError as exc:
            raise OSError(
                f"{exc}; {self.stats.get('frames_sent', 0)} frames / "
                f"{self.stats.get('bytes_on_wire', 0)} bytes accepted before failure"
            ) from exc
        self.stats["frames_sent"] += 1
        self.stats["bytes_on_wire"] += len(frame_bytes)

    def _await(self, predicate, timeout: float) -> Frame | None:
        """Drain the socket until predicate(frame) matches or the timeout ends."""
        deadline = monotonic() + timeout
        while True:
            remaining = deadline - monotonic()
            if remaining <= 0:
                return None
            packet = self.link.recvfrom(remaining)
            if packet is None:
                continue
            data, _addr = packet            if _addr != self.peer:                self.stats["rx_stray"] += 1                continue
            try:
                frame = parse_frame(data)
            except FrameError:
                self.stats["rx_bad_frames"] += 1
                continue
            if frame.transfer_id != self.transfer_id:
                self.stats["rx_stray"] += 1
                continue
            if predicate(frame):
                return frame
            self.stats["rx_unrelated"] += 1

    # --- transfer stages ----------------------------------------------------

    def run(self, trigger: InferTrigger | None = None) -> dict:
        self.stats = {
            "transfer_id": self.transfer_id,
            "peer": f"{self.peer[0]}:{self.peer[1]}",
            "bin": str(self.bin_path),
            "packets_unique": 0,
            "retransmitted": 0,
            "loss_events": 0,
            "batches_total": 0,
            "frames_sent": 0,
            "bytes_on_wire": 0,
            "rx_bad_frames": 0,
            "rx_stray": 0,
            "rx_unrelated": 0,
            "ready_status": None,
            "ready": None,
            "infer_status": None,
            "infer_result": None,
        }
        started = monotonic()
        try:
            self._stage_image_begin()
            self._stage_batches()
            self._stage_image_end()
            if trigger is not None:
                self._stage_inference(trigger)
        except TransferError:
            self._send_abort_quietly()
            raise
        finally:
            if self._file is not None:
                self._file.close()
                self._file = None
        self.stats["duration_s"] = monotonic() - started
        payload = self.params.total_bytes
        self.stats["payload_mib"] = payload / (1024 * 1024)
        self.stats["throughput_mib_s"] = payload / (1024 * 1024) / max(self.stats["duration_s"], 1e-9)
        return self.stats

    def _stage_image_begin(self) -> None:
        sequence = self._alloc_seq()   # first allocation is 0 (doc §5.2)
        frame_bytes = build_frame(
            MSG_IMAGE_BEGIN, self.transfer_id, sequence, self.params.body()
        )
        for attempt in range(1, self.config.begin_retries + 1):
            self._send(frame_bytes)
            ack_frame = self._await(
                lambda f: f.msg_type == MSG_ACK
                and parse_ack_body(f.body).acked_msg_type == MSG_IMAGE_BEGIN
                and parse_ack_body(f.body).acked_sequence == sequence,
                self.config.begin_timeout,
            )
            if ack_frame is None:
                self.log(f"[send] IMAGE_BEGIN ACK timeout, attempt {attempt}/"
                      f"{self.config.begin_retries} (receiver up?)", flush=True)
                continue
            ack = parse_ack_body(ack_frame.body)
            if ack.status != ACK_ACCEPTED:
                raise TransferError(
                    f"IMAGE_BEGIN rejected: {ACK_STATUSES.get(ack.status, hex(ack.status))} "
                    f"reason=0x{ack.reason:04X}"
                )
            return
        raise TransferError(
            f"no ACK for IMAGE_BEGIN after {self.config.begin_retries} attempts "
            f"(peer {self.peer[0]}:{self.peer[1]})"
        )

    def _stage_batches(self) -> None:
        self._stage_start = monotonic()
        params = self.params
        batch_count = (params.total_slices + params.batch_slices - 1) // params.batch_slices
        self.stats["batches_total"] = batch_count
        self._file = self.bin_path.open("rb")
        batch_index = 0
        first_slice = 0
        while first_slice < params.total_slices:
            slice_ids = list(range(
                first_slice,
                min(first_slice + params.batch_slices, params.total_slices),
            ))
            self._transfer_batch(batch_index, slice_ids)
            first_slice += len(slice_ids)
            batch_index += 1
            if batch_index % PROGRESS_EVERY_BATCHES == 0 or first_slice >= params.total_slices:
                self.log(f"[send] progress: batch {batch_index}/{batch_count}, "
                      f"slices {first_slice}/{params.total_slices}, "
                      f"retransmitted {self.stats['retransmitted']} packets, "
                      f"{monotonic() - self._stage_start:.1f}s", flush=True)

    def _transfer_batch(self, batch_index: int, slice_ids: list[int]) -> None:
        # Build every data frame once; a retransmission resends the identical
        # bytes so Transfer_ID/Slice_ID/Packet_Idx/Sequence all stay fixed.
        frames: dict[tuple[int, int], bytes] = {}
        pending: list[tuple[int, int]] = []
        batch_crc = 0
        for slice_id in slice_ids:
            slice_bytes = self._read_slice(slice_id)
            batch_crc = zlib.crc32(slice_bytes, batch_crc)
            for packet_idx in range(PACKETS_PER_SLICE):
                start = packet_idx * PACKET_PIXEL_BYTES
                body = build_image_data_body(
                    slice_id, packet_idx, slice_bytes[start:start + PACKET_PIXEL_BYTES]
                )
                frames[(slice_id, packet_idx)] = build_frame(
                    MSG_IMAGE_DATA, self.transfer_id, self._alloc_seq(), body
                )
                pending.append((slice_id, packet_idx))
        batch_crc &= 0xFFFFFFFF
        expected = len(slice_ids) * PACKETS_PER_SLICE
        self.stats["packets_unique"] += expected
        batch_id = batch_index & 0xFFFF

        attempts = 0
        while True:
            attempts += 1
            self._send_pending(frames, pending)
            end_body = build_batch_end_body(
                batch_id, slice_ids[0], len(slice_ids), expected, batch_crc
            )
            self._send(build_frame(
                MSG_BATCH_END, self.transfer_id, self._alloc_seq(), end_body
            ))
            status_frame = self._await(
                lambda f, bid=batch_id: f.msg_type == MSG_BATCH_STATUS
                and parse_batch_status_body(f.body).batch_id == bid,
                self.config.status_timeout,
            )
            if status_frame is None:
                if attempts >= self.config.max_batch_attempts:
                    raise TransferError(
                        f"batch {batch_index}: no BATCH_STATUS after {attempts} attempts"
                    )
                self.log(f"[send] batch {batch_index}: BATCH_STATUS timeout, retrying "
                      f"(attempt {attempts})", flush=True)
                continue

            status = parse_batch_status_body(status_frame.body)
            if status.expected_packets != expected or status.received_packets > expected:
                raise TransferError(f"batch {batch_index}: inconsistent packet counts")
            if status.status == BATCH_COMPLETE:
                if status.received_packets != expected:
                    raise TransferError(f"batch {batch_index}: COMPLETE with missing packets")
                return
            if status.status == BATCH_MISSING and status.bitmap:
                if len(status.bitmap) != (expected + 7) // 8:
                    raise TransferError(f"batch {batch_index}: invalid bitmap length")
                missing = bitmap_to_missing(status.bitmap, expected)
                if len(missing) != expected - status.received_packets:
                    raise TransferError(f"batch {batch_index}: bitmap/count mismatch")
                pending = [
                    (slice_ids[index // PACKETS_PER_SLICE], index % PACKETS_PER_SLICE)
                    for index in missing
                ]
                self.stats["retransmitted"] += len(pending)
                self.stats["loss_events"] += 1
                self.log(f"[send] batch {batch_index} slices "
                      f"{slice_ids[0]}..{slice_ids[-1]}: {len(pending)}/{expected} "
                      f"packets missing, retransmitting (attempt {attempts})", flush=True)
                if attempts >= self.config.max_batch_attempts:
                    raise TransferError(
                        f"batch {batch_index}: still missing packets after "
                        f"{attempts} attempts"
                    )
                continue
            raise TransferError(
                f"batch {batch_index}: BATCH_STATUS error status 0x{status.status:02X}"
            )

    def _send_pending(self, frames: dict[tuple[int, int], bytes],
                      pending: list[tuple[int, int]]) -> None:
        for count, key in enumerate(pending):
            self._send(frames[key])
            if self.config.pace_us and count % self.config.pace_every == self.config.pace_every - 1:
                sleep(self.config.pace_us / 1e6)

    def _read_slice(self, slice_id: int) -> bytes:
        self._file.seek(slice_id * SLICE_BYTES)
        data = self._file.read(SLICE_BYTES)
        if len(data) != SLICE_BYTES:
            raise TransferError(f"BIN truncated at slice {slice_id}")
        return data

    def _stage_image_end(self) -> None:
        body = build_image_end_body(
            self.params.expected_packets, self.params.total_bytes,
            self.params.whole_crc32,
        )
        for attempt in range(1, self.config.ready_retries + 1):
            self._send(build_frame(MSG_IMAGE_END, self.transfer_id,
                                   self._alloc_seq(), body))
            ready_frame = self._await(
                lambda f: f.msg_type == MSG_IMAGE_READY,
                self.config.ready_timeout,
            )
            if ready_frame is not None:
                ready = parse_image_ready_body(ready_frame.body)
                self.stats["ready_status"] = ready.status
                self.stats["ready"] = {
                    "received_slices": ready.received_slices,
                    "received_packets": ready.received_packets,
                    "received_bytes": ready.received_bytes,
                    "calculated_crc32": ready.calculated_crc32,
                    "image_base_addr": ready.image_base_addr,
                }
                if ready.status == READY_DDR_ERROR:
                    raise TransferError(
                        "FPGA returned READY_DDR_ERROR: this communication-only bitstream "
                        "does not store the image in DDR. Use src/fpga_link_check.py to "
                        "check the link; full transfer needs the DDR implementation."
                    )
                if ready.status != READY_OK:
                    raise TransferError(
                        f"IMAGE_READY status 0x{ready.status:02X}: received "
                        f"{ready.received_packets}/{self.params.expected_packets} "
                        f"packets, crc 0x{ready.calculated_crc32:08X}"
                    )
                if (ready.received_slices != self.params.total_slices
                        or ready.received_packets != self.params.expected_packets
                        or ready.received_bytes != self.params.total_bytes
                        or ready.image_base_addr != self.params.image_base_addr
                        or ready.calculated_crc32 != self.params.whole_crc32):
                    raise TransferError("IMAGE_READY metadata/CRC does not match the sent image")
                return
        raise TransferError(
            f"no IMAGE_READY after {self.config.ready_retries} attempts"
        )

    def _stage_inference(self, trigger: InferTrigger) -> None:
        body = build_infer_trigger_body(trigger)
        for attempt in range(1, self.config.ready_retries + 1):
            self._send(build_frame(MSG_INFER_TRIGGER, self.transfer_id,
                                   self._alloc_seq(), body))
            done_frame = self._await(
                lambda f: f.msg_type == MSG_INFER_DONE
                and parse_infer_done_body(f.body).task_id == trigger.task_id,
                self.config.ready_timeout,
            )
            if done_frame is not None:
                done = parse_infer_done_body(done_frame.body)
                self.stats["infer_status"] = done.status
                self.stats["infer_result"] = f"0x{done.result_value:08X}"
                if done.status != 0x00:
                    raise TransferError(
                        f"INFER_DONE status 0x{done.status:02X}"
                    )
                return
        raise TransferError(
            f"no INFER_DONE after {self.config.ready_retries} attempts"
        )

    def _send_abort_quietly(self) -> None:
        try:
            self._send(build_frame(MSG_TRANSFER_ABORT, self.transfer_id,
                                   self._alloc_seq(), b""))
        except OSError:
            pass
