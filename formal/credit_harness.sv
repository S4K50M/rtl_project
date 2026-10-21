module credit_harness(input clk,rst,send,consume,input [7:0] data);
    wire [7:0] head;
    wire empty,full;
    wire [2:0] count;
    reg [2:0] credit;
    wire push=send && credit!=0 && !rst;
    wire pop=consume && !empty && !rst;
    noc_fifo #(.WIDTH(8),.DEPTH(4)) dut(clk,rst,push,pop,data,head,empty,full,count);
    reg past_valid=0;
    always @(posedge clk) begin
        past_valid<=1;
        if(!past_valid) assume(rst); else assume(!rst);
        if(rst) credit<=4;
        else begin
            case({pop,push})
                2'b10: credit<=credit+1'b1;
                2'b01: credit<=credit-1'b1;
                default: ;
            endcase
            assert(count<=4);
            assert(credit<=4);
            assert({1'b0,credit}+{1'b0,count}==4);
            assert(!(push && full));
            assert(!(pop && empty));
        end
    end
endmodule
