`timescale 1ns/1ps
`include "noc_defs.vh"
module tb_traffic;
    parameter NX=2,NY=2,FAST=0;
    localparam N=NX*NY;
    reg clk=0,rst=1,enable=0,hotspot=0;
    reg [15:0] rate=0;
    always #5 clk=~clk;
    wire [N*64-1:0] tx,rx,ifl,efl;
    wire [N-1:0] tv,tr,rv,iv,ic,ev,ec;
    reg [N-1:0] rr=0;
    wire [31:0] injected[0:N-1];
    integer delivered=0,cycles=0,total=0,flitpos[0:N-1],src[0:N-1],ident[0:N-1];
    reg [4095:0] seen[0:N-1];
    noc_mesh #(.NX(NX),.NY(NY),.FAST(FAST)) mesh(clk,rst,ifl,iv,ic,efl,ev,ec);
    genvar n;
    generate for(n=0;n<N;n=n+1) begin: nodes
        traffic_source #(.NODE(n),.NX(NX),.NY(NY),.SEED(32'h24ba7831+n)) source(clk,rst,enable,hotspot,rate,tx[n*64+:64],tv[n],tr[n],injected[n]);
        noc_endpoint ep(clk,rst,tx[n*64+:64],tv[n],tr[n],rx[n*64+:64],rv[n],rr[n],ifl[n*64+:64],iv[n],ic[n],efl[n*64+:64],ev[n],ec[n]);
    end endgenerate
    always @(posedge clk) if(!rst) begin
        cycles=cycles+1;
        for(integer n=0;n<N;n=n+1) if(rv[n] && rr[n]) begin
            if(flitpos[n]==0) begin
                if(!rx[n*64+`HEAD] || rx[n*64+60+:2]!=n%NX || rx[n*64+58+:2]!=n/NX) $fatal(1,"Traffic header misroute");
                src[n]=rx[n*64+54+:2]*NX+rx[n*64+56+:2]; ident[n]=rx[n*64+8+:24];
                if(seen[src[n]][ident[n]]) $fatal(1,"Duplicate traffic packet");
                flitpos[n]=1;
            end else begin
                if(rx[n*64+`HEAD] || rx[n*64+:8]!=flitpos[n] || rx[n*64+8+:24]!=ident[n]) $fatal(1,"Traffic data/interleaving error");
                if(flitpos[n]==2) begin
                    if(!rx[n*64+`TAIL]) $fatal(1,"Traffic missing tail");
                    seen[src[n]][ident[n]]=1; delivered=delivered+1; flitpos[n]=0;
                end else flitpos[n]=2;
            end
        end
    end
    always @(negedge clk) for(integer i=0;i<N;i=i+1) rr[i]=(cycles+i*7)%13<8;
    initial begin
        for(integer i=0;i<N;i=i+1) begin seen[i]=0; flitpos[i]=0; src[i]=0; ident[i]=0; end
        repeat(5) @(negedge clk); rst=0; enable=1; rate=16'h9000;
        repeat(600) @(negedge clk); hotspot=1; rate=16'hf000;
        repeat(900) @(negedge clk); enable=0;
        repeat(2000) @(negedge clk);
        for(integer i=0;i<N;i=i+1) total=total+injected[i];
        if(delivered!=total || total<40) $fatal(1,"Traffic loss injected=%0d delivered=%0d",total,delivered);
        $display("HARDWARE TRAFFIC PASS NX=%0d FAST=%0d packets=%0d",NX,FAST,total); $finish;
    end
endmodule
