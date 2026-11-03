"""Wire codec for the CT-FPGA UDP transfer protocol V1 (doc/网口传输协议规定.md).

Frame layout, all integers big-endian:

    Magic(2)=0x55AA  Version(1)=0x01  Msg_Type(1)  Transfer_ID(4)
    Header_Len(2)=16 Body_Len(2)      Sequence(4)  Body(...)
    CRC32(4)         Tail(2)=0xAA55

CRC-32/ISO-HDLC (zlib.crc32) covers every byte from Version through the last
Body byte; Magic, the CRC field itself and Tail are excluded.
"""

from dataclasses import dataclass, field
import struct
import zlib

MAGIC = 0x55AA
TAIL = 0xAA55
VERSION = 0x01
HEADER_LEN = 16

# --- Msg_Type values (doc §6) ------------------------------------------------
MSG_IMAGE_DATA = 0x01
MSG_INFER_TRIGGER = 0x02
MSG_IMAGE_BEGIN = 0x03
MSG_IMAGE_END = 0x04
MSG_BATCH_END = 0x05
MSG_TRANSFER_ABORT = 0x06
MSG_ACK = 0x81
MSG_INFER_DONE = 0x82
MSG_BATCH_STATUS = 0x83
MSG_IMAGE_READY = 0x84
MSG_ERROR = 0xE0

MSG_NAMES = {
    MSG_IMAGE_DATA: "IMAGE_DATA",
    MSG_INFER_TRIGGER: "INFER_TRIGGER",
    MSG_IMAGE_BEGIN: "IMAGE_BEGIN",
    MSG_IMAGE_END: "IMAGE_END",
    MSG_BATCH_END: "BATCH_END",
    MSG_TRANSFER_ABORT: "TRANSFER_ABORT",
    MSG_ACK: "ACK",
    MSG_INFER_DONE: "INFER_DONE",
    MSG_BATCH_STATUS: "BATCH_STATUS",
    MSG_IMAGE_READY: "IMAGE_READY",
    MSG_ERROR: "ERROR",
}

# --- Fixed data contract values (doc §3, §7.3) --------------------------------
HU_MIN = -1024
HU_MAX = 1000
WIDTH = 512
HEIGHT = 512
SLICE_BYTES = WIDTH * HEIGHT                    # 262144
PACKET_PIXEL_BYTES = 1024
PACKETS_PER_SLICE = SLICE_BYTES // PACKET_PIXEL_BYTES   # 256
DEPTH = 33
CENTER_INDEX = 16
PATCH_SIZE = 96

DTYPE_INT8 = 0x01
LAYOUT_ZYX = 0x01
Z_BOUNDARY_REPEAT = 0x01
ROUNDING_NP_RINT = 0x01
XY_PADDING_EDGE = 0x01
TARGET_CENTER_SLICE_ONLY = 0x01
QUANTIZATION_ID = 0x00000001

# --- ACK status (doc §17) ------------------------------------------------------
ACK_ACCEPTED = 0x00
ACK_BUSY = 0x01
ACK_INVALID_PARAMETER = 0x02
ACK_CRC_ERROR = 0x03
ACK_DDR_ERROR = 0x04
ACK_NOT_READY = 0x05
ACK_STATUSES = {
    ACK_ACCEPTED: "ACCEPTED",
    ACK_BUSY: "BUSY",
    ACK_INVALID_PARAMETER: "INVALID_PARAMETER",
    ACK_CRC_ERROR: "CRC_ERROR",
    ACK_DDR_ERROR: "DDR_ERROR",
    ACK_NOT_READY: "NOT_READY",
}

# --- BATCH_STATUS status (doc §10) --------------------------------------------
BATCH_COMPLETE = 0x00
BATCH_MISSING = 0x01
BATCH_CRC_ERROR = 0x02
BATCH_PARAM_ERROR = 0x03
BATCH_BUSY = 0x04
BATCH_DDR_ERROR = 0x05

# --- IMAGE_READY status (doc §12) ----------------------------------------------
READY_OK = 0x00
READY_MISSING = 0x01
READY_CRC_ERROR = 0x02
READY_DDR_ERROR = 0x03
READY_PARAM_MISMATCH = 0x04

# --- INFER_DONE status (doc §16) -----------------------------------------------
INFER_OK = 0x00
INFER_BUSY = 0x01
INFER_NOT_READY = 0x02
INFER_PARAM_ERROR = 0x03
INFER_DDR_ERROR = 0x04
INFER_MODEL_ERROR = 0x05

INFER_RESULT_DUMMY = 0xDEADBEEF


class FrameError(ValueError):
    """Raised when a received frame violates the V1 framing rules."""


@dataclass
class Frame:
    msg_type: int
    transfer_id: int
    sequence: int
    body: bytes


# --- Generic frame codec -------------------------------------------------------

_HEADER = struct.Struct(">HBBIHHI")   # Magic, Version, Msg_Type, Transfer_ID, Header_Len, Body_Len, Sequence
_TRAILER = struct.Struct(">IH")       # CRC32, Tail


def build_frame(msg_type: int, transfer_id: int, sequence: int, body: bytes) -> bytes:
    header = _HEADER.pack(
        MAGIC, VERSION, msg_type, transfer_id, HEADER_LEN, len(body), sequence
    )
    # CRC covers Version..Body end, i.e. everything except Magic, CRC itself and Tail.
    crc = zlib.crc32(header[2:] + body) & 0xFFFFFFFF
    return header + body + _TRAILER.pack(crc, TAIL)


def parse_frame(data: bytes) -> Frame:
    min_len = HEADER_LEN + _TRAILER.size
    if len(data) < min_len:
        raise FrameError(f"frame too short: {len(data)} bytes")
    magic, version, msg_type, transfer_id, header_len, body_len, sequence = (
        _HEADER.unpack_from(data, 0)
    )
    if magic != MAGIC:
        raise FrameError(f"bad magic 0x{magic:04X}")
    if version != VERSION:
        raise FrameError(f"unsupported version 0x{version:02X}")
    if header_len != HEADER_LEN:
        raise FrameError(f"bad header length {header_len}")
    total = HEADER_LEN + body_len + _TRAILER.size
    if len(data) < total:
        raise FrameError(f"truncated frame: {len(data)} < {total}")
    body = bytes(data[HEADER_LEN:HEADER_LEN + body_len])
    crc_stored, tail = _TRAILER.unpack_from(data, HEADER_LEN + body_len)
    if tail != TAIL:
        raise FrameError(f"bad tail 0x{tail:04X}")
    crc_calc = zlib.crc32(data[2:HEADER_LEN + body_len]) & 0xFFFFFFFF
    if crc_stored != crc_calc:
        raise FrameError(f"CRC mismatch: stored 0x{crc_stored:08X} != calc 0x{crc_calc:08X}")
    return Frame(msg_type, transfer_id, sequence, body)


def describe(msg_type: int) -> str:
    return MSG_NAMES.get(msg_type, f"0x{msg_type:02X}")


# --- IMAGE_BEGIN (doc §7) ------------------------------------------------------

_IMAGE_BEGIN_FMT = ">IHHBBBBIIIQQIIIIiiBBBBHHHH"
_IMAGE_BEGIN_LEN = 76


@dataclass
class ImageBegin:
    total_slices: int
    width: int = WIDTH
    height: int = HEIGHT
    bytes_per_pixel: int = 1
    dtype_code: int = DTYPE_INT8
    layout_code: int = LAYOUT_ZYX
    z_boundary_code: int = Z_BOUNDARY_REPEAT
    packet_pixel_bytes: int = PACKET_PIXEL_BYTES
    packets_per_slice: int = PACKETS_PER_SLICE
    slice_stride_bytes: int = SLICE_BYTES
    total_bytes: int = 0
    image_base_addr: int = 0
    batch_slices: int = 1
    expected_packets: int = 0
    whole_crc32: int = 0
    quantization_id: int = QUANTIZATION_ID
    hu_min: int = HU_MIN
    hu_max: int = HU_MAX
    rounding_code: int = ROUNDING_NP_RINT
    xy_padding_code: int = XY_PADDING_EDGE
    target_code: int = TARGET_CENTER_SLICE_ONLY
    depth: int = DEPTH
    center_index: int = CENTER_INDEX
    patch_size: int = PATCH_SIZE

    def body(self) -> bytes:
        values = (
            self.total_slices, self.width, self.height,
            self.bytes_per_pixel, self.dtype_code, self.layout_code,
            self.z_boundary_code,
            self.packet_pixel_bytes, self.packets_per_slice,
            self.slice_stride_bytes,
            self.total_bytes, self.image_base_addr,
            self.batch_slices, self.expected_packets,
            self.whole_crc32, self.quantization_id,
            self.hu_min, self.hu_max,
            self.rounding_code, self.xy_padding_code, self.target_code, 0,
            self.depth, self.center_index, self.patch_size, 0,
        )
        body = struct.pack(_IMAGE_BEGIN_FMT, *values)
        assert len(body) == _IMAGE_BEGIN_LEN
        return body


def parse_image_begin(body: bytes) -> ImageBegin:
    if len(body) < _IMAGE_BEGIN_LEN:
        raise FrameError(f"IMAGE_BEGIN body too short: {len(body)}")
    (total_slices, width, height, bpp, dtype_code, layout, z_boundary,
     packet_bytes, packets_per_slice, stride, total_bytes, base_addr,
     batch_slices, expected_packets, whole_crc, quant_id, hu_min, hu_max,
     rounding, xy_pad, target, _r1, depth, center_idx, patch_size,
     _r2) = struct.unpack_from(_IMAGE_BEGIN_FMT, body, 0)
    return ImageBegin(
        total_slices=total_slices, width=width, height=height,
        bytes_per_pixel=bpp, dtype_code=dtype_code, layout_code=layout,
        z_boundary_code=z_boundary, packet_pixel_bytes=packet_bytes,
        packets_per_slice=packets_per_slice, slice_stride_bytes=stride,
        total_bytes=total_bytes, image_base_addr=base_addr,
        batch_slices=batch_slices, expected_packets=expected_packets,
        whole_crc32=whole_crc, quantization_id=quant_id,
        hu_min=hu_min, hu_max=hu_max, rounding_code=rounding,
        xy_padding_code=xy_pad, target_code=target,
        depth=depth, center_index=center_idx, patch_size=patch_size,
    )


def check_fpga_requirements(begin: ImageBegin) -> str | None:
    """Return the first violated §7.3 requirement, or None when acceptable."""
    checks = (
        (begin.bytes_per_pixel == 1, "Bytes_Per_Pixel != 1"),
        (begin.width == WIDTH, f"Width != {WIDTH}"),
        (begin.height == HEIGHT, f"Height != {HEIGHT}"),
        (begin.dtype_code == DTYPE_INT8, "DType_Code != signed int8"),
        (begin.packets_per_slice == PACKETS_PER_SLICE,
         f"Packets_Per_Slice != {PACKETS_PER_SLICE}"),
        (begin.packet_pixel_bytes == PACKET_PIXEL_BYTES,
         f"Packet_Pixel_Bytes != {PACKET_PIXEL_BYTES}"),
        (begin.slice_stride_bytes == SLICE_BYTES,
         f"Slice_Stride_Bytes != {SLICE_BYTES}"),
        (begin.depth == DEPTH, f"Depth != {DEPTH}"),
        (begin.center_index == CENTER_INDEX, f"Center_Index != {CENTER_INDEX}"),
        (begin.patch_size == PATCH_SIZE, f"Patch_Size != {PATCH_SIZE}"),
        (begin.total_slices >= 1, "Total_Slices < 1"),
        (begin.batch_slices >= 1, "Batch_Slices < 1"),
        (begin.total_bytes == begin.total_slices * SLICE_BYTES,
         "Total_Bytes != Total_Slices * 262144"),
        (begin.expected_packets == begin.total_slices * PACKETS_PER_SLICE,
         "Expected_Packets != Total_Slices * 256"),
        (begin.image_base_addr % 4096 == 0, "Image_Base_Addr not 4KB aligned"),
    )
    for ok, message in checks:
        if not ok:
            return message
    return None


# --- IMAGE_DATA (doc §8) -------------------------------------------------------

_IMAGE_DATA_HEAD = struct.Struct(">HHHH")   # Slice_ID, Packet_Idx, Pixel_Len, Reserved


def build_image_data_body(slice_id: int, packet_idx: int, pixels: bytes) -> bytes:
    if len(pixels) != PACKET_PIXEL_BYTES:
        raise ValueError(f"pixel payload must be {PACKET_PIXEL_BYTES} bytes")
    return _IMAGE_DATA_HEAD.pack(slice_id, packet_idx, len(pixels), 0) + pixels


def parse_image_data_body(body: bytes) -> tuple[int, int, int, bytes]:
    if len(body) != _IMAGE_DATA_HEAD.size + PACKET_PIXEL_BYTES:
        raise FrameError(f"IMAGE_DATA body length {len(body)}")
    slice_id, packet_idx, pixel_len, _reserved = _IMAGE_DATA_HEAD.unpack_from(body, 0)
    pixels = bytes(body[_IMAGE_DATA_HEAD.size:])
    return slice_id, packet_idx, pixel_len, pixels


# --- BATCH_END (doc §9) --------------------------------------------------------

_BATCH_END = struct.Struct(">HHHHII")


def build_batch_end_body(batch_id: int, first_slice_id: int, slice_count: int,
                         expected_packets: int, batch_crc32: int) -> bytes:
    return _BATCH_END.pack(batch_id, first_slice_id, slice_count, 0,
                           expected_packets, batch_crc32)


def parse_batch_end_body(body: bytes) -> tuple[int, int, int, int, int]:
    if len(body) != _BATCH_END.size:
        raise FrameError(f"BATCH_END body length {len(body)}")
    batch_id, first_slice, count, _reserved, expected, crc = _BATCH_END.unpack_from(body, 0)
    return batch_id, first_slice, count, expected, crc


# --- BATCH_STATUS (doc §10) ----------------------------------------------------

_BATCH_STATUS_HEAD = struct.Struct(">HBBIIHH")  # Batch_ID, Status, Rsv, Expected, Received, Bitmap_Bytes, Rsv


@dataclass
class BatchStatus:
    batch_id: int
    status: int
    expected_packets: int
    received_packets: int
    bitmap: bytes = field(default=b"")


def build_batch_status_body(batch_id: int, status: int, expected: int,
                            received: int, missing_bitmap: bytes | None) -> bytes:
    bitmap = missing_bitmap if missing_bitmap is not None else b""
    head = _BATCH_STATUS_HEAD.pack(batch_id, status, 0, expected, received,
                                   len(bitmap), 0)
    return head + bitmap


def parse_batch_status_body(body: bytes) -> BatchStatus:
    if len(body) < _BATCH_STATUS_HEAD.size:
        raise FrameError(f"BATCH_STATUS body too short: {len(body)}")
    batch_id, status, _r1, expected, received, bitmap_len, _r2 = (
        _BATCH_STATUS_HEAD.unpack_from(body, 0)
    )
    bitmap = bytes(body[_BATCH_STATUS_HEAD.size:_BATCH_STATUS_HEAD.size + bitmap_len])
    return BatchStatus(batch_id, status, expected, received, bitmap)


# Missing-bitmap helpers. Convention (shared by both ends, must match the FPGA
# implementation later): packet index i maps to byte i // 8, bit (7 - i % 8),
# i.e. MSB-first within each byte, as in doc §10 bit = 1 means missing.

def missing_to_bitmap(missing_indices, packet_count: int) -> bytes:
    bitmap = bytearray((packet_count + 7) // 8)
    for index in missing_indices:
        bitmap[index // 8] |= 1 << (7 - index % 8)
    return bytes(bitmap)


def bitmap_to_missing(bitmap: bytes, packet_count: int) -> list[int]:
    missing = []
    for index in range(packet_count):
        if bitmap[index // 8] >> (7 - index % 8) & 1:
            missing.append(index)
    return missing


# --- IMAGE_END (doc §11) -------------------------------------------------------

_IMAGE_END = struct.Struct(">IQII")


def build_image_end_body(expected_packets: int, expected_bytes: int,
                         whole_crc32: int, flags: int = 0) -> bytes:
    return _IMAGE_END.pack(expected_packets, expected_bytes, whole_crc32, flags)


def parse_image_end_body(body: bytes) -> tuple[int, int, int, int]:
    if len(body) != _IMAGE_END.size:
        raise FrameError(f"IMAGE_END body length {len(body)}")
    return _IMAGE_END.unpack_from(body, 0)


# --- IMAGE_READY (doc §12) -----------------------------------------------------

_IMAGE_READY = struct.Struct(">B3sIIQIQ")


@dataclass
class ImageReady:
    status: int
    received_slices: int
    received_packets: int
    received_bytes: int
    calculated_crc32: int
    image_base_addr: int


def build_image_ready_body(status: int, received_slices: int, received_packets: int,
                           received_bytes: int, calculated_crc32: int,
                           image_base_addr: int) -> bytes:
    return _IMAGE_READY.pack(status, b"\x00\x00\x00", received_slices,
                             received_packets, received_bytes, calculated_crc32,
                             image_base_addr)


def parse_image_ready_body(body: bytes) -> ImageReady:
    if len(body) != _IMAGE_READY.size:
        raise FrameError(f"IMAGE_READY body length {len(body)}")
    status, _rsv, slices_, packets_, bytes_, crc, base = _IMAGE_READY.unpack_from(body, 0)
    return ImageReady(status, slices_, packets_, bytes_, crc, base)


# --- INFER_TRIGGER (doc §13) ---------------------------------------------------

_INFER_TRIGGER = struct.Struct(">IIHHHHHHI")


@dataclass
class InferTrigger:
    task_id: int
    center_slice_id: int
    patch_start_y: int
    patch_start_x: int
    depth: int = DEPTH
    center_index: int = CENTER_INDEX
    patch_size: int = PATCH_SIZE
    model_id: int = 1


def build_infer_trigger_body(trigger: InferTrigger) -> bytes:
    return _INFER_TRIGGER.pack(
        trigger.task_id, trigger.center_slice_id, trigger.patch_start_y,
        trigger.patch_start_x, trigger.depth, trigger.center_index,
        trigger.patch_size, trigger.model_id, 0,
    )


def parse_infer_trigger_body(body: bytes) -> InferTrigger:
    if len(body) != _INFER_TRIGGER.size:
        raise FrameError(f"INFER_TRIGGER body length {len(body)}")
    task_id, center, py, px, depth, center_idx, patch_size, model_id, _r = (
        _INFER_TRIGGER.unpack_from(body, 0)
    )
    return InferTrigger(task_id, center, py, px, depth, center_idx, patch_size, model_id)


# --- INFER_DONE (doc §16) ------------------------------------------------------

_INFER_DONE = struct.Struct(">IIBBHI")


@dataclass
class InferDone:
    task_id: int
    center_slice_id: int
    status: int
    result_type: int
    result_len: int
    result_value: int


def build_infer_done_body(task_id: int, center_slice_id: int, status: int,
                          result_type: int = 0, result_len: int = 4,
                          result_value: int = INFER_RESULT_DUMMY) -> bytes:
    return _INFER_DONE.pack(task_id, center_slice_id, status, result_type,
                            result_len, result_value)


def parse_infer_done_body(body: bytes) -> InferDone:
    if len(body) != _INFER_DONE.size:
        raise FrameError(f"INFER_DONE body length {len(body)}")
    task_id, center, status, result_type, result_len, value = _INFER_DONE.unpack_from(body, 0)
    return InferDone(task_id, center, status, result_type, result_len, value)


# --- ACK (doc §17) -------------------------------------------------------------

_ACK = struct.Struct(">BBHI")


@dataclass
class Ack:
    acked_msg_type: int
    status: int
    reason: int
    acked_sequence: int


def build_ack_body(acked_msg_type: int, status: int, reason: int = 0,
                   acked_sequence: int = 0) -> bytes:
    return _ACK.pack(acked_msg_type, status, reason, acked_sequence)


def parse_ack_body(body: bytes) -> Ack:
    if len(body) != _ACK.size:
        raise FrameError(f"ACK body length {len(body)}")
    msg_type, status, reason, sequence = _ACK.unpack_from(body, 0)
    return Ack(msg_type, status, reason, sequence)
