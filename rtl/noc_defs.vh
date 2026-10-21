`ifndef NOC_DEFS_VH
`define NOC_DEFS_VH
// 64-bit flit. Coordinates support meshes up to 4x4; port order L,E,W,S,N.
`define HEAD 63
`define TAIL 62
`define DX 61:60
`define DY 59:58
`define SX 57:56
`define SY 55:54
`define OP 53:51
`define TAG 50:43
`define STRB 42:39
`define RESP 38:37
`define DATA 31:0
`define RD_REQ 3'd0
`define WR_REQ 3'd1
`define RD_RESP 3'd2
`define WR_RESP 3'd3
`endif
