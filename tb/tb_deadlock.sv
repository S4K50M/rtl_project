`timescale 1ns/1ps
`include "noc_defs.vh"
module tb_deadlock;
    parameter MIXED=1;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [255:0] tx;
    reg [3:0] tv;
    wire [3:0] tr,rv,iv,ic,ev,ec;
    wire [255:0] rx,ifl,efl;
    integer index[0:3];
    integer delivered=0;
    noc_mesh #(.ALLOW_MIXED(MIXED)) mesh(clk,rst,ifl,iv,ic,efl,ev,ec);
    genvar n;
    generate for(n=0;n<4;n=n+1) begin: endpoints
        noc_endpoint ep(clk,rst,tx[n*64+:64],tv[n],tr[n],rx[n*64+:64],rv[n],1'b1,
            ifl[n*64+:64],iv[n],ic[n],efl[n*64+:64],ev[n],ec[n]);
        always @(posedge clk) begin
            if(rst) index[n]<=0;
            else if(tv[n] && tr[n]) index[n]<=index[n]+1;
        end
    end endgenerate
    always @* begin
        tx=0; tv=0;
        for(integer i=0;i<4;i=i+1) begin
            tv[i]=index[i]<8;
            tx[i*64+`HEAD]=index[i]==0;
            tx[i*64+`TAIL]=index[i]==7;
            tx[i*64+60+:2]=(3-i)%2;
            tx[i*64+58+:2]=(3-i)/2;
            tx[i*64+36]=(i==1 || i==2);
            tx[i*64+:32]=i*256+index[i];
        end
    end
    always @(posedge clk) if(!rst)
        for(integer i=0;i<4;i=i+1) if(rv[i]) delivered=delivered+1;
    initial begin
        if(MIXED) $dumpfile("build/deadlock.vcd");
        else $dumpfile("build/xy_control.vcd");
        $dumpvars(0,tb_deadlock);
        repeat(4) @(negedge clk); rst=0;
        repeat(150) @(negedge clk);
        if(MIXED) begin
            if(delivered!=0 ||
               mesh.rows[0].cols[0].router.occupancy[3]!=4 ||
               mesh.rows[0].cols[1].router.occupancy[2]!=4 ||
               mesh.rows[1].cols[1].router.occupancy[4]!=4 ||
               mesh.rows[1].cols[0].router.occupancy[1]!=4 ||
               mesh.rows[0].cols[0].router.credits[1]!=0 ||
               mesh.rows[0].cols[1].router.credits[3]!=0 ||
               mesh.rows[1].cols[1].router.credits[2]!=0 ||
               mesh.rows[1].cols[0].router.credits[4]!=0) $fatal(1,"Deadlock state not reached");
            repeat(100) begin
                @(negedge clk);
                if(|mesh.ov[0] || |mesh.ov[1] || |mesh.ov[2] || |mesh.ov[3]) $fatal(1,"Expected fixed-point deadlock");
            end
            $display("EXPECTED DEADLOCK: four full buffers, zero credits, cyclic ownership, 100 idle cycles");
        end else if(delivered!=32) $fatal(1,"XY control did not drain: %0d flits",delivered);
        else $display("XY DEADLOCK CONTROL PASS: all 32 flits delivered");
        $finish;
    end
endmodule
