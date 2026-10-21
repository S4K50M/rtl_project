`timescale 1ns/1ps
module tb_core;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    wire valid,ready,write,rsp_ready,halted,trap;
    wire [31:0] addr,wdata,pc;
    wire [3:0] strb;
    reg [31:0] memory[0:4095];
    reg rsp_valid=0,error=0,busy=0;
    reg [31:0] response=0,lfsr=32'h5ac39077;
    integer delay_cycles=0,phase=0;
    assign ready=!busy && !rsp_valid && lfsr[0];
    rv32_core dut(clk,rst,valid,ready,write,addr,wdata,strb,rsp_valid,rsp_ready,response,error,halted,trap,pc);
    always @(posedge clk) begin
        lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
        if(rst) begin busy<=0; rsp_valid<=0; error<=0; end
        else begin
            if(valid && ready) begin
                if(addr>=16384 || addr[1:0]) $fatal(1,"Core bad address");
                if(write) for(integer b=0;b<4;b=b+1) if(strb[b]) memory[addr>>2][b*8+:8]<=wdata[b*8+:8];
                response<=memory[addr>>2];
                busy<=1; delay_cycles<=lfsr[3:1];
            end
            if(busy) begin
                if(delay_cycles==0) begin busy<=0; rsp_valid<=1; end
                else delay_cycles<=delay_cycles-1;
            end
            if(rsp_valid && rsp_ready) rsp_valid<=0;
        end
    end
    initial begin
        $readmemh("build/isa.hex",memory);
        repeat(5) @(negedge clk); rst=0;
        wait(halted); @(negedge clk);
        if(trap || memory[1024]!==32'h600dcafe) $fatal(1,"ISA test failed pc=%h case=%0d",pc,memory[1024]);
        $display("RV32I directed ISA PASS checks=%0d",dut.regs[28]);
        // Misaligned LW must trap before issuing a bus operation.
        rst=1; repeat(3) @(negedge clk);
        memory[0]=32'h00102083; // lw x1,1(x0)
        rst=0; wait(halted); @(negedge clk);
        if(!trap) $fatal(1,"Expected misalignment trap");
        rst=1; repeat(3) @(negedge clk);
        memory[0]=32'h020000b3; // MUL: unsupported extension
        rst=0; wait(halted); @(negedge clk);
        if(!trap) $fatal(1,"Expected illegal instruction trap");
        $display("RV32 fault checks PASS"); $finish;
    end
    initial begin repeat(50000) @(posedge clk); $fatal(1,"Core timeout"); end
endmodule
