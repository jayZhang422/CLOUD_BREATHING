// Dual-plane mesh RTL ABI 0x00050000.
// FP64 triangles/candidate planes remain in DDR; the RTL core returns FP64
// volume/area and integer diagnostics.  No Q-format conversion is permitted
// on this path. Each 160-byte candidate has four 32-byte planes followed by
// a float64 ridge origin (x,y,z) and one reserved float64 word.
`ifndef DUAL_PLANE_MESH_ABI_VH
`define DUAL_PLANE_MESH_ABI_VH
`define DPM_ABI_VERSION       32'h00050000
`define DPM_BASE               32'hA0012000
`define DPM_CONTROL            12'h000
`define DPM_TRIANGLE_COUNT     12'h004
`define DPM_CANDIDATE_COUNT    12'h008
`define DPM_JOB_ID             12'h00c
`define DPM_VERSION            12'h014
`define DPM_ERRORS             12'h018
`define DPM_MESH_LO            12'h020
`define DPM_MESH_HI            12'h024
`define DPM_CANDIDATES_LO      12'h028
`define DPM_CANDIDATES_HI      12'h02c
`define DPM_SEGMENTS_LO        12'h030
`define DPM_SEGMENTS_HI        12'h034
`define DPM_RESULTS_LO         12'h038
`define DPM_RESULTS_HI         12'h03c
`define DPM_SEGMENT_CAPACITY   12'h040
`define DPM_RESULT_COUNT       12'h044
`define DPM_CYCLES             12'h048
`define DPM_BVH_LO             12'h050
`define DPM_BVH_HI             12'h054
`define DPM_BVH_COUNT          12'h058
`define DPM_CENTER_X_LO        12'h060
`define DPM_CENTER_X_HI        12'h064
`define DPM_CENTER_Y_LO        12'h068
`define DPM_CENTER_Y_HI        12'h06c
`define DPM_CENTER_Z_LO        12'h070
`define DPM_CENTER_Z_HI        12'h074
`define DPM_PROF_CAND_READ     12'h080
`define DPM_PROF_BVH_READ      12'h084
`define DPM_PROF_BVH_CLASSIFY  12'h088
`define DPM_PROF_MESH_READ     12'h08c
`define DPM_PROF_CLIP_SEGMENT  12'h090
`define DPM_PROF_REDUCE        12'h094
`define DPM_PROF_OTHER         12'h098
`define DPM_PROF_AR_COUNT      12'h09c
`define DPM_PROF_AR_LATENCY    12'h0a0
`define DPM_ERR_OPEN_LOOP      8'h02
`define DPM_ERR_SEGMENT_OVF    8'h04
`define DPM_ERR_ABORT          8'h08
`define DPM_ERR_TIMEOUT        8'h10
`define DPM_ERR_BINDING_CAP    8'h20
`define DPM_ERR_NUMERIC        8'h40
`define DPM_ERR_DESCRIPTOR     8'h80
`endif
