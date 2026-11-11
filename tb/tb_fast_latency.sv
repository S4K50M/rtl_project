`timescale 1ns/1ps
`include "noc_defs.vh"
// Directed 1-flit, zero-load 0 -> 3 test for the FAST 2x2 mesh.
// Expected header acceptance -> tail reception = 7 cycles.
module tb_fast_latency;
    localparam NX=2, NY=2, N=4;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [63:0] input_flit=0;
    reg input_valid=0;
    wire input_ready;
    wire [N*64-1:0] inject_flit, eject_flit;
    wire [N-1:0] inject_valid, inject_credit, eject_valid, eject_credit;
    wire [63:0] rx_data;
    wire rx_valid;
    integer cycle=0, inject_cycle=-1, receive_cycle=-1;

    // Source node 0, destination node 3. Other mesh endpoints idle.
    noc_endpoint source_ep (
       .clk(clk),.rst(rst),.tx_data(input_flit),.tx_valid(input_valid),
       .tx_ready(input_ready),.rx_data(),.rx_valid(),.rx_ready(1'b1),
       .inject_flit(inject_flit[0+:64]),.inject_valid(inject_valid[0]),
       .inject_credit(inject_credit[0]),.eject_flit(eject_flit[0+:64]),
       .eject_valid(eject_valid[0]),.eject_credit(eject_credit[0])
    );
    genvar g;
    generate for(g=1;g<N;g=g+1) begin : sinks
        wire [63:0] dummy_rx;
        wire dummy_valid;
        noc_endpoint ep (
          .clk(clk),.rst(rst),.tx_data(64'b0),.tx_valid(1'b0),
          .tx_ready(),.rx_data(dummy_rx),.rx_valid(dummy_valid),
          .rx_ready(1'b1),
          .inject_flit(inject_flit[g*64+:64]),
          .inject_valid(inject_valid[g]),.inject_credit(inject_credit[g]),
          .eject_flit(eject_flit[g*64+:64]),.eject_valid(eject_valid[g]),
          .eject_credit(eject_credit[g])
        );
    end endgenerate

    noc_mesh_fast #(.NX(2),.NY(2)) dut (
      .clk(clk),.rst(rst),.inject_flit(inject_flit),
      .inject_valid(inject_valid),.inject_credit(inject_credit),
      .eject_flit(eject_flit),.eject_valid(eject_valid),
      .eject_credit(eject_credit)
    );

    always @(posedge clk) if(!rst) begin
        // Sample handshakes immediately before NBA sequential updates.
        if(input_valid && input_ready) inject_cycle=cycle;
        if(sinks[3].dummy_valid) begin
            if(receive_cycle!=-1) $fatal(1,"Duplicate received flit");
            receive_cycle=cycle;
            if(!sinks[3].dummy_rx[`HEAD] || !sinks[3].dummy_rx[`TAIL])
                $fatal(1,"Incorrect single-flit packet");
            if(inject_cycle<0) $fatal(1,"Packet received before injection");
            if(receive_cycle-inject_cycle != 7)
                $fatal(1,"FAST latency wrong: got %0d expected 7",receive_cycle-inject_cycle);
            $display("FAST SINGLE-FLIT LATENCY PASS: %0d cycles",receive_cycle-inject_cycle);
            $finish;
        end
        cycle=cycle+1;
        if(cycle>100) $fatal(1,"Timeout waiting for FAST packet");
    end
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        // Header and tail both asserted, destination (1,1), source (0,0).
        input_flit=64'b0;
        input_flit[`HEAD]=1'b1;
        input_flit[`TAIL]=1'b1;
        input_flit[`DX]=2'd1;
        input_flit[`DY]=2'd1;
        input_valid=1'b1;
        @(negedge clk);
        input_valid=1'b0;
    end
endmodule
