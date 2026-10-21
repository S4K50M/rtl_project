module uart_tx #(parameter CLK_HZ=50000000,BAUD=115200)(
    input wire clk,rst,valid, input wire [7:0] data,
    output wire ready, output wire tx
);
    localparam DIV=CLK_HZ/BAUD;
    reg [31:0] count;
    reg [3:0] bits_left;
    reg [9:0] shift;
    assign ready=bits_left==0;
    assign tx=ready?1'b1:shift[0];
    always @(posedge clk) begin
        if(rst) begin count<=0; bits_left<=0; shift<=10'h3ff; end
        else if(ready) begin
            if(valid) begin shift<={1'b1,data,1'b0}; bits_left<=10; count<=DIV-1; end
        end else if(count==0) begin
            shift<={1'b1,shift[9:1]}; bits_left<=bits_left-1'b1; count<=DIV-1;
        end else count<=count-1'b1;
    end
endmodule
