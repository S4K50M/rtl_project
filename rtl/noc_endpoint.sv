// Converts a ready/valid stream to the local port's credit protocol.
module noc_endpoint #(parameter DEPTH=4)(
    input wire clk,rst,
    input wire [63:0] tx_data,
    input wire tx_valid,
    output wire tx_ready,
    output wire [63:0] rx_data,
    output wire rx_valid,
    input wire rx_ready,
    output wire [63:0] inject_flit,
    output wire inject_valid,
    input wire inject_credit,
    input wire [63:0] eject_flit,
    input wire eject_valid,
    output wire eject_credit
);
    reg [$clog2(DEPTH+1)-1:0] credits;
    wire empty,full;
    wire [$clog2(DEPTH+1)-1:0] count;
    assign tx_ready=credits!=0 && !rst;
    assign inject_valid=tx_valid && tx_ready;
    assign inject_flit=tx_data;
    assign rx_valid=!empty && !rst;
    assign eject_credit=rx_valid && rx_ready;
    noc_fifo #(.DEPTH(DEPTH)) rx(clk,rst,eject_valid,eject_credit,eject_flit,rx_data,empty,full,count);
    always @(posedge clk) begin
        if(rst) credits<=DEPTH;
        else case({inject_credit,inject_valid})
            2'b10: credits<=credits+1'b1;
            2'b01: credits<=credits-1'b1;
            default: ;
        endcase
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst && credits>DEPTH) $fatal(1,"Endpoint credit overflow");
`endif
endmodule
