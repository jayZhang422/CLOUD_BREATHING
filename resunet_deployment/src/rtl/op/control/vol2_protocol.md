# VOL2 FPGA Contract

VOL1 remains unchanged: its START header and native INT8 upload continue to use
the existing image receiver, Q16 coordinate maps, and transform kinds 2/3.
VOL2 uses the same 0x26 START, 0x27 QUERY, 0x28 RELEASE, 0x29 ABORT, 96-byte
manifest records, and 32-byte DDR memory interface. Its compact-view transform
is kind 4.

The PC `ct_volume_vol2.bin` container begins with `<4sHHII>`: magic `VOL2`,
version 2, section count, source depth, and descriptor-table byte count. Each
40-byte `<8sBBHIIIIHHII>` section entry contains name, direction flags, boundary
flags (bit 0 means repeat-edge), file offset, DDR base, plane count, byte length,
width, height, row stride, and plane stride. Payload offsets and DDR bases are
32-byte aligned. Native signed INT8 remains separately stored as the compatibility
baseline.

## START header

The 64-byte START body contains little-endian 32-bit words:

| Word | Meaning | VOL2 value |
|---|---|---|
| 0 | magic | `0x324C4F56` (`VOL2`) |
| 1 | version | `2` |
| 2 | manifest base | `0x08200000` |
| 3 | manifest record count | 1..65536 |
| 4 | canonical image base | `0x00400000` |
| 5 | original CT depth | 1..480 |
| 6 | result base | `0x10000000` |
| 7 | result bytes | `depth * 524288` |
| 8..15 | reserved | zero |

VOL2 does not require the legacy IMAGE_READY latch. The host uploads the
sections of the compact BIN to DDR while storage is idle, then uploads the
manifest and starts the job. Each kind-4 command identifies its own source
section, so the bundle can place model-facing layouts in separate DDR ranges.
Source sections may occupy `0x00400000..0x08000000` or the free range after the
result allocation up to `0x30000000` (`VIEW_TOP` in `op_volume_service`); they
must not overlap parameters, maps, scratch tensors, or results. Each command is
checked against those ranges. The host READ/WRITE limit (`HOST_DDR_TOP` in
`op_service`) is the same `0x30000000`, so sections above `0x20000000` can be
uploaded.

`0x1E000000..0x20000000` is still reserved for the fixed decoder concat skip
mapping in `op_engine`. The RTL accepts any view that ends at or below
`VIEW_TOP`, so the host layout (`plan_views` in `vol2.py` / `vol2.cpp`) is
responsible for keeping every section out of that window. Operator descriptor
ranges (`op_descriptor_check`) are unchanged and still end at `0x20000000`.

Rationale: with 334 slices only about 57 MiB remain after the result region,
which cannot hold the 84 MiB transposed native view (`native_t`). Without it the
airway/tumor gathers use orientation 1, every compact-line lookup misses the
eight-line cache, and the volume run is about 140-170 s slower.

## Kind-4 command

The 64-byte command is little-endian. The first 44 bytes are:

| Byte offset | Width | Meaning |
|---|---:|---|
| 0 | 1 | kind = 4 |
| 1 | 1 | orientation: bits 1:0 are 0 native, 1 transpose, 2 transpose plus X/Y reversal; bit 2 marks reverse source-Z direction |
| 2 | 1 | resample tag: 0 identity, 1 lobe Q16/RNE data already resampled by PC |
| 3 | 1 | reserved, zero |
| 4 | 4 | this view's DDR base |
| 8 | 4 | destination P16 base |
| 12 | 4 | number of planes in this view |
| 16 | 4 | byte length of this view |
| 20 | 2 | valid width, 1..512 |
| 22 | 2 | valid height, 1..512 |
| 24 | 4 | row stride in bytes, at least width |
| 28 | 4 | plane stride in bytes, at least row_stride * height |
| 32 | 4 | previous input plane index |
| 36 | 4 | center input plane index |
| 40 | 4 | next input plane index |
| 44..63 | 20 | reserved, zero |

Planes are signed INT8 and row-major with X contiguous. The three indices are
explicit in output channel order. At a Z boundary, repeat the edge plane index
(for example `0,0,1` at the first output plane and `N-2,N-1,N-1` at the last).
The orientation selects the same XY mapping as VOL1. Bit 2 records the source
Z direction; the explicit indices carry the actual neighbor order. `row_stride`
and `plane_stride` permit aligned padding while keeping each plane and row
readable as linear bursts.

The FPGA centers the valid width/height in its 512x512 output grid, applies the
selected XY orientation, and writes signed `-128` for every out-of-grid sample. In-grid reads use one byte per
channel and the existing eight-line cache. The existing two-pixel/32-byte
write FIFO and response tracking are reused.

For lobe, the compact view contains the PC-resampled grid. Its samples must
match the current `fpga_volume_io.resample_int8` contract: align-corners Q16
coordinates, round-to-even coordinate quantization, one final signed
round-to-even result, then INT8 saturation. The FPGA reads these samples
directly; it does not interpolate them a second time.

## Compatibility and validation

VOL1 START validation and kind-2/kind-3 command interpretation remain separate
from VOL2. Kind 4 is rejected unless START selected VOL2. A VOL2 command is
rejected for invalid dimensions, strides, plane indices, view bounds, or a
source/destination address outside the allowed DDR regions.

The Python producer must emit the same START words and command offsets, place
the three directional/lobe sections in safe DDR ranges, preserve the legacy
INT8 artifact, and compare the compact lobe bytes against the fixed-point
reference before sending them.
