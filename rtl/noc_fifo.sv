module noc_fifo #(parameter WIDTH=64, DEPTH=4)(
    input wire clk, rst,
    input wire push, pop,
    input wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout,
    output wire empty, full,
    output reg [$clog2(DEPTH+1)-1:0] count
);
    localparam PW=(DEPTH<=2)?1:$clog2(DEPTH);
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PW-1:0] rd,wr;
    assign empty=(count==0);
    assign full=(count==DEPTH);
    assign dout=mem[rd];
    always @(posedge clk) begin
        if(rst) begin rd<=0; wr<=0; count<=0; end
        else begin
            if(push) begin mem[wr]<=din; wr <= (wr==DEPTH-1)?0:wr+1'b1; end
            if(pop) rd <= (rd==DEPTH-1)?0:rd+1'b1;
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: ;
            endcase
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst) begin
        if(push && full && !pop) $fatal(1,"FIFO overflow");
        if(pop && empty) $fatal(1,"FIFO underflow");
    end
`endif
endmodule
