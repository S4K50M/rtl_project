`timescale 1ns/1ps
module tb_divider;
    reg clk=0,rst=1,start=0;
    always #5 clk=~clk;
    reg [63:0] numerator,expected;
    reg [31:0] denominator;
    wire busy,done;
    wire [63:0] quotient;
    integer f,rc,cases=0;
    unsigned_divider dut(clk,rst,start,numerator,denominator,busy,done,quotient);
    initial begin
        f=$fopen("build/divider.in","r");
        repeat(3) @(negedge clk); rst=0;
        while(!$feof(f)) begin
            rc=$fscanf(f,"%h %h %h",numerator,denominator,expected);
            if(rc==3) begin
                start=1; @(negedge clk); start=0;
                wait(done); #1;
                if(quotient!==expected || busy) $fatal(1,"Divider mismatch %h/%h expected=%h got=%h",numerator,denominator,expected,quotient);
                cases=cases+1;
                @(negedge clk); @(negedge clk);
            end
        end
        $display("DIVIDER PASS vectors=%0d",cases); $finish;
    end
    initial begin repeat(50000) @(posedge clk); $fatal(1,"Divider timeout"); end
endmodule
