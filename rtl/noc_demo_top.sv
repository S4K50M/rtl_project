module noc_demo_top #(parameter FAST=0,MEM_FILE="build/firmware.hex",CLK_HZ=50000000,BAUD=115200)(
    input wire clk,input wire reset_n,
    output wire uart_tx,output wire done,trap,
    output wire [31:0] exit_code,
    output wire uart_event,output wire [7:0] uart_byte
);
    // Asynchronous assertion, synchronous deassertion. All logic uses one clock.
    reg [1:0] reset_sync;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) reset_sync<=0; else reset_sync<={reset_sync[0],1'b1};
    wire rst=!reset_sync[1];
    wire req_valid,req_ready,req_write,rsp_valid,rsp_ready,rsp_error,halted;
    wire [31:0] req_addr,req_wdata,rsp_data,pc;
    wire [3:0] req_wstrb;
    wire [31:0] awaddr,wdata,araddr,rdata;
    wire [3:0] wstrb;
    wire awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
    wire [1:0] bresp,rresp;
    wire [31:0] stat_count,stat_mean,stat_variance;
    rv32_core core(clk,rst,req_valid,req_ready,req_write,req_addr,req_wdata,req_wstrb,
        rsp_valid,rsp_ready,rsp_data,rsp_error,halted,trap,pc);
    rv32_axi_adapter adapter(clk,rst,req_valid,req_ready,req_write,req_addr,req_wdata,req_wstrb,
        rsp_valid,rsp_ready,rsp_data,rsp_error,awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
        araddr,arvalid,arready,rdata,rresp,rvalid,rready);
    noc_soc_fabric #(.FAST(FAST),.MEM_FILE(MEM_FILE),.CLK_HZ(CLK_HZ),.BAUD(BAUD)) fabric(clk,rst,
        awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
        araddr,arvalid,arready,rdata,rresp,rvalid,rready,uart_tx,uart_event,uart_byte,done,exit_code,
        stat_count,stat_mean,stat_variance);
endmodule
