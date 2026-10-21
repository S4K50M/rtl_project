`include "noc_defs.vh"
// One outstanding AXI4-Lite transaction. AW and W are captured independently.
module axi_noc_host (
    input wire clk,rst,
    input wire [31:0] s_awaddr,
    input wire s_awvalid, output wire s_awready,
    input wire [31:0] s_wdata, input wire [3:0] s_wstrb,
    input wire s_wvalid, output wire s_wready,
    output reg [1:0] s_bresp, output wire s_bvalid, input wire s_bready,
    input wire [31:0] s_araddr, input wire s_arvalid, output wire s_arready,
    output reg [31:0] s_rdata, output reg [1:0] s_rresp,
    output wire s_rvalid, input wire s_rready,
    output reg [63:0] tx_data, output wire tx_valid, input wire tx_ready,
    input wire [63:0] rx_data, input wire rx_valid, output wire rx_ready,
    output reg sample_valid, output reg [31:0] sample_latency,input wire sample_ready
);
    localparam IDLE=0,HEADER=1,BODY=2,WAIT_RESPONSE=3,BRESP=4,RRESP=5;
    reg [2:0] state;
    reg aw_hold,w_hold,writing;
    reg [31:0] addr,awaddr,wdata,ticks,started;
    reg [3:0] strb;
    reg [7:0] tag;
    reg [1:0] dx,dy;
    assign s_awready=state==IDLE && !aw_hold && !rst;
    assign s_wready=state==IDLE && !w_hold && !rst;
    assign s_arready=state==IDLE && !aw_hold && !w_hold && !s_awvalid && !s_wvalid && !rst;
    assign s_bvalid=state==BRESP;
    assign s_rvalid=state==RRESP;
    assign tx_valid=state==HEADER || state==BODY;
    assign rx_ready=state==WAIT_RESPONSE && sample_ready;
    always @* begin
        tx_data=0;
        if(state==HEADER) begin
            tx_data[`HEAD]=1;
            tx_data[`TAIL]=!writing;
            tx_data[`DX]=dx; tx_data[`DY]=dy;
            tx_data[`OP]=writing?`WR_REQ:`RD_REQ;
            tx_data[`TAG]=tag;
            tx_data[`STRB]=strb;
            tx_data[`DATA]=addr;
        end else begin
            tx_data[`TAIL]=1;
            tx_data[`DATA]=wdata;
        end
    end
    task destination(input [31:0] a);
        begin
            case(a[31:28])
                0: begin dx<=1; dy<=0; end
                1: begin dx<=0; dy<=1; end
                default: begin dx<=1; dy<=1; end
            endcase
        end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; aw_hold<=0; w_hold<=0; tag<=0; ticks<=0;
            writing<=0; addr<=0; awaddr<=0; wdata<=0; strb<=0; dx<=0; dy<=0;
            s_rdata<=0; s_rresp<=0; s_bresp<=0; started<=0; sample_valid<=0; sample_latency<=0;
        end else begin
            ticks<=ticks+1'b1; sample_valid<=0;
            if(s_awvalid && s_awready) begin awaddr<=s_awaddr; aw_hold<=1; end
            if(s_wvalid && s_wready) begin wdata<=s_wdata; strb<=s_wstrb; w_hold<=1; end
            case(state)
                IDLE: begin
                    if(aw_hold && w_hold) begin
                        addr<=awaddr; destination(awaddr); writing<=1;
                        state<=HEADER; aw_hold<=0; w_hold<=0; started<=ticks;
                    end else if(s_arvalid && s_arready) begin
                        addr<=s_araddr; destination(s_araddr); writing<=0;
                        state<=HEADER; started<=ticks;
                    end
                end
                HEADER: if(tx_ready) state<=writing?BODY:WAIT_RESPONSE;
                BODY: if(tx_ready) state<=WAIT_RESPONSE;
                WAIT_RESPONSE: if(rx_valid && rx_ready) begin
                    sample_valid<=1; sample_latency<=ticks-started;
                    s_rdata<=rx_data[`DATA]; s_rresp<=rx_data[`RESP]; s_bresp<=rx_data[`RESP];
                    state<=writing?BRESP:RRESP;
                end
                BRESP: if(s_bready) begin state<=IDLE; tag<=tag+1'b1; end
                RRESP: if(s_rready) begin state<=IDLE; tag<=tag+1'b1; end
                default: state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst && rx_valid && rx_ready) begin
        if(!rx_data[`HEAD] || !rx_data[`TAIL] || rx_data[`TAG]!=tag ||
           rx_data[`OP]!=(writing?`WR_RESP:`RD_RESP)) $fatal(1,"Bad response packet");
    end
`endif
endmodule
