`timescale 1ns/1ps
module tb_stats;
    reg clk=0,rst=1,valid=0;
    reg [31:0] latency=0;
    wire [31:0] count,mean_q16,variance_q16;
    wire ready;
    always #5 clk=~clk;
    welford_stats #(.MAX_SAMPLES(64)) dut(clk,rst,valid,latency,count,mean_q16,variance_q16,ready);
    integer fi,fo,rc,reset_input,valid_input;
    initial begin
        fi=$fopen("build/stats.in","r"); fo=$fopen("build/stats.out","w");
        repeat(3) @(negedge clk);
        while(!$feof(fi)) begin
            rc=$fscanf(fi,"%d %d %d",reset_input,valid_input,latency);
            if(rc==3) begin
                rst=reset_input; valid=valid_input;
                @(posedge clk); #1; valid=0;
                if(!reset_input && valid_input) begin
                    while(!ready) begin @(posedge clk); #1; end
                end
                $fwrite(fo,"%0d %0d %0d\n",count,mean_q16,variance_q16);
                @(negedge clk);
            end
        end
        $fclose(fi); $fclose(fo); $display("RTL Welford trace PASS"); $finish;
    end
endmodule
