`timescale 1ns/1ps
module tb_axi;
    parameter FAST=0,MEM_FILE="build/firmware.hex";
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] awaddr=0,wdata=0,araddr=0;
    reg [3:0] wstrb=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata,exit_code,count,mean_q16,var_q16;
    wire uart,ev,done;
    wire [7:0] byte_out;
    reg [31:0] expected[0:31];
    reg [31:0] random_state=32'h95af1e21;
    reg [31:0] v;
    reg [3:0] st;
    integer transactions=0;
    noc_soc_fabric #(.FAST(FAST),.MEM_FILE(MEM_FILE),.CLK_HZ(10000000),.BAUD(1000000)) dut(clk,rst,
        awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
        araddr,arvalid,arready,rdata,rresp,rvalid,rready,uart,ev,byte_out,done,exit_code,count,mean_q16,var_q16);
    task send_aw(input [31:0] a,input integer delay_cycles);
        begin
            repeat(delay_cycles+1) @(negedge clk);
            awaddr=a; awvalid=1;
            do @(posedge clk); while(!awready);
            @(negedge clk); awvalid=0;
        end
    endtask
    task send_w(input [31:0] d,input [3:0] s,input integer delay_cycles);
        begin
            repeat(delay_cycles+1) @(negedge clk);
            wdata=d; wstrb=s; wvalid=1;
            do @(posedge clk); while(!wready);
            @(negedge clk); wvalid=0;
        end
    endtask
    task write_word(input [31:0] a,d,input [3:0] s,input integer ad,wd,input [1:0] response);
        begin
            fork send_aw(a,ad); send_w(d,s,wd); join
            while(!bvalid) @(negedge clk);
            repeat(4) begin
                if(!bvalid || bresp!==response) $fatal(1,"AXI B unstable/wrong %h",bresp);
                @(negedge clk);
            end
            bready=1; @(posedge clk); @(negedge clk); bready=0;
            transactions=transactions+1;
        end
    endtask
    task read_word(input [31:0] a,expected_data,input [1:0] response,input check_data);
        begin
            @(negedge clk); araddr=a; arvalid=1;
            do @(posedge clk); while(!arready);
            @(negedge clk); arvalid=0;
            while(!rvalid) @(negedge clk);
            repeat(5) begin
                if(!rvalid || rresp!==response || (check_data && rdata!==expected_data))
                    $fatal(1,"AXI read addr=%h expected=%h got=%h response=%h",a,expected_data,rdata,rresp);
                @(negedge clk);
            end
            rready=1; @(posedge clk); @(negedge clk); rready=0;
            transactions=transactions+1;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0;
        for(integer i=0;i<32;i=i+1) begin
            expected[i]=32'hdead0000+i;
            write_word(32'h2000+4*i,expected[i],15,i%3,(i+1)%4,0);
        end
        for(integer i=0;i<64;i=i+1) begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            v=random_state; st=random_state[7:4];
            write_word(32'h2000+4*(i%32),v,st,(i+3)%7,i%7,0);
            for(integer b=0;b<4;b=b+1) if(st[b]) expected[i%32][8*b+:8]=v[8*b+:8];
            read_word(32'h2000+4*(i%32),expected[i%32],0,1);
        end
        read_word(32'hffff0000,0,3,0);
        write_word(32'hffff0000,1,15,0,3,3);
        read_word(32'h20000000,0,0,0);
        read_word(32'h00000001,0,3,0);
        write_word(32'h00000001,1,15,3,0,3);
        // Concurrent read held while AW arrives before W: no AW/W pairing loss.
        fork
            write_word(32'h2000,32'h12345678,15,0,12,0);
            begin repeat(3) @(negedge clk); read_word(32'h2000,32'h12345678,0,1); end
        join
        // Exercise uniform background clients concurrently with CPU accesses.
        write_word(32'h10000020,32'h40000001,15,2,0,0);
        for(integer i=0;i<20;i=i+1) read_word(32'h2000,32'h12345678,0,1);
        write_word(32'h10000020,0,15,0,2,0);
        repeat(200) @(negedge clk);
        read_word(32'h10000034,0,0,1);
        if(dut.injected_total==0 || dut.injected_total!=dut.delivered_total) $fatal(1,"Live traffic did not drain");
        // Synchronous fabric reset flushes in-flight protocol state.
        send_aw(32'h2000,0);
        rst=1; repeat(4) @(negedge clk); rst=0;
        write_word(32'h2000,32'hb0a7cafe,15,4,0,0);
        read_word(32'h2000,32'hb0a7cafe,0,1);
        wait(dut.sample_ready); @(negedge clk);
        if(count<2) $fatal(1,"Statistics not active");
        $display("AXI PASS FAST=%0d transactions=%0d",FAST,transactions); $finish;
    end
    initial begin repeat(100000) @(posedge clk); $fatal(1,"AXI timeout"); end
endmodule
