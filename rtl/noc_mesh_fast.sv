// Explicit FAST=1 mesh variant. Reuses the verified router implementation.
// Every router inside noc_mesh is instantiated with FAST=1.
module noc_mesh_fast #(
    parameter NX=2, NY=2, DEPTH=4, MINIMIZED=0
)(
    input wire clk, rst,
    input wire [NX*NY*64-1:0] inject_flit,
    input wire [NX*NY-1:0] inject_valid,
    output wire [NX*NY-1:0] inject_credit,
    output wire [NX*NY*64-1:0] eject_flit,
    output wire [NX*NY-1:0] eject_valid,
    input wire [NX*NY-1:0] eject_credit
);
    noc_mesh #(
        .NX(NX), .NY(NY), .DEPTH(DEPTH),
        .FAST(1), .MINIMIZED(MINIMIZED), .ALLOW_MIXED(0)
    ) fast_mesh (
        .clk(clk), .rst(rst),
        .inject_flit(inject_flit), .inject_valid(inject_valid),
        .inject_credit(inject_credit),
        .eject_flit(eject_flit), .eject_valid(eject_valid),
        .eject_credit(eject_credit)
    );
endmodule
