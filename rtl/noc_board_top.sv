// Minimal physical I/O wrapper. The oscillator frequency and all package pins
// must come from the exact board's manual/master XDC.
module noc_board_top #(parameter CLK_HZ=50000000,BAUD=115200,FAST=0)(
    input wire clk,reset_n,output wire uart_tx
);
    wire done,trap,event_byte;
    wire [7:0] data;
    wire [31:0] code;
    (* keep_hierarchy="yes" *) noc_demo_top #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.FAST(FAST)) demo(
        clk,reset_n,uart_tx,done,trap,code,event_byte,data);
endmodule
