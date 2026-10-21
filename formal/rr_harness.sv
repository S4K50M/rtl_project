module rr_harness(input clk,rst,advance,input [4:0] request);
    wire [4:0] grant;
    rr_arbiter dut(clk,rst,advance,request,grant);
    reg past_valid=0;
    reg [2:0] waited;
    always @(posedge clk) begin
        past_valid<=1;
        if(!past_valid) assume(rst);
        else assume(!rst);
        if(rst) waited<=0;
        else begin
            assert((grant & (grant-1'b1))==0);
            assert((grant & ~request)==0);
            assert((grant!=0)==(request!=0));
            assert(waited<5);
            if(!request[0] || (grant[0] && advance)) waited<=0;
            else if(advance) waited<=waited+1'b1;
        end
    end
endmodule
