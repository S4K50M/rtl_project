`timescale 1ns/1ps
module tb_mesh;
    parameter NX=2,NY=2,FAST=0,MINIMIZED=0;
    localparam N=NX*NY;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [N*64-1:0] tx=0;
    reg [N-1:0] valid=0,ready=0;
    wire [N-1:0] txready,rxvalid,iv,ic,ev,ec;
    wire [N*64-1:0] rx,ifl,efl;
    noc_mesh #(.NX(NX),.NY(NY),.FAST(FAST),.MINIMIZED(MINIMIZED)) mesh(clk,rst,ifl,iv,ic,efl,ev,ec);
    genvar n;
    generate for(n=0;n<N;n=n+1) begin: endpoints
        noc_endpoint ep(clk,rst,tx[n*64+:64],valid[n],txready[n],rx[n*64+:64],rxvalid[n],ready[n],
            ifl[n*64+:64],iv[n],ic[n],efl[n*64+:64],ev[n],ec[n]);
    end endgenerate
    integer stimulus,results,rc,cycles;
    reg [63:0] value;
    string input_file,output_file;
    initial begin
        if(!$value$plusargs("INPUT=%s",input_file) || !$value$plusargs("OUTPUT=%s",output_file)) $fatal(1,"Missing files");
        stimulus=$fopen(input_file,"r"); results=$fopen(output_file,"w");
        if(!stimulus || !results) $fatal(1,"Cannot open trace files");
        repeat(3) @(negedge clk);
        rst=0; cycles=0;
        while(!$feof(stimulus)) begin
            rc=$fscanf(stimulus,"%h %h",valid,ready);
            if(rc==2) begin
                for(integer i=0;i<N;i=i+1) begin
                    rc=$fscanf(stimulus,"%h",value);
                    if(rc!=1) $fatal(1,"Malformed stimulus");
                    tx[i*64+:64]=value;
                end
                #1;
                $fwrite(results,"%h %h",txready,rxvalid);
                for(integer i=0;i<N;i=i+1) $fwrite(results," %016h",rx[i*64+:64]);
                $fwrite(results,"\n");
                cycles=cycles+1;
                @(negedge clk);
            end
        end
        $fclose(stimulus); $fclose(results);
        $display("MESH TRACE PASS NX=%0d NY=%0d FAST=%0d cycles=%0d",NX,NY,FAST,cycles); $finish;
    end
endmodule
