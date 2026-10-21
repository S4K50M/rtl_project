`timescale 1ns/1ps
module tb_soc;
    parameter FAST=0,MEM_FILE="build/firmware.hex";
    reg clk=0,reset_n=0;
    always #5 clk=~clk;
    wire uart,done,trap,event_byte;
    wire [31:0] exit_code;
    wire [7:0] data;
    integer chars=0,serial_chars=0;
    reg [7:0] observed [0:1023];
    noc_demo_top #(.FAST(FAST),.MEM_FILE(MEM_FILE),.CLK_HZ(10000000),.BAUD(1000000)) dut(clk,reset_n,uart,done,trap,exit_code,event_byte,data);
    always @(posedge clk) begin
        if(event_byte) begin $write("%c",data); observed[chars]=data; chars=chars+1; end
        if(trap) $fatal(1,"RV32 trap at PC %h instruction %h",dut.core.pc,dut.core.insn);
    end
    // Decode the actual serial pin, independently of the debug byte event.
    initial forever begin
        @(negedge uart);
        repeat(15) @(posedge clk);
        for(integer b=0;b<8;b=b+1) begin
            if(uart!==observed[serial_chars][b]) $fatal(1,"UART bit mismatch");
            repeat(10) @(posedge clk);
        end
        if(uart!==1) $fatal(1,"UART stop bit");
        serial_chars=serial_chars+1;
    end
    initial begin
        repeat(5) @(negedge clk); reset_n=1;
        wait(done);
        repeat(200) @(posedge clk);
        if(exit_code!=0 || chars<100 || serial_chars!=chars || dut.stat_count<100)
            $fatal(1,"SoC result code=%0d chars=%0d serial=%0d",exit_code,chars,serial_chars);
        $display("SOC PASS FAST=%0d transactions=%0d",FAST,dut.stat_count); $finish;
    end
    initial begin repeat(1000000) @(posedge clk); $fatal(1,"SoC timeout"); end
endmodule
