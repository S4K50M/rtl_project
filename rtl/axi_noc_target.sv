`include "noc_defs.vh"
module axi_noc_target #(parameter X=1,Y=0)(
    input wire clk,rst,
    input wire [63:0] rx_data, input wire rx_valid, output wire rx_ready,
    output reg [63:0] tx_data, output wire tx_valid, input wire tx_ready,
    output wire [31:0] m_awaddr, output wire m_awvalid, input wire m_awready,
    output wire [31:0] m_wdata, output wire [3:0] m_wstrb,
    output wire m_wvalid, input wire m_wready,
    input wire [1:0] m_bresp, input wire m_bvalid, output wire m_bready,
    output wire [31:0] m_araddr, output wire m_arvalid, input wire m_arready,
    input wire [31:0] m_rdata, input wire [1:0] m_rresp,
    input wire m_rvalid, output wire m_rready
);
    localparam RX_HEADER=0,RX_BODY=1,WRITE=2,READ=3,TX=4;
    reg [2:0] state;
    reg [31:0] addr,data,result;
    reg [3:0] strb;
    reg [1:0] sx,sy,resp;
    reg [7:0] tag;
    reg writing,aw_done,w_done,ar_done;
    assign rx_ready=(state==RX_HEADER || state==RX_BODY) && !rst;
    assign tx_valid=state==TX;
    assign m_awaddr=addr; assign m_wdata=data; assign m_wstrb=strb;
    assign m_araddr=addr;
    assign m_awvalid=state==WRITE && !aw_done;
    assign m_wvalid=state==WRITE && !w_done;
    assign m_arvalid=state==READ && !ar_done;
    assign m_bready=state==WRITE && aw_done && w_done;
    assign m_rready=state==READ && ar_done;
    always @* begin
        tx_data=0; tx_data[`HEAD]=1; tx_data[`TAIL]=1;
        tx_data[`DX]=sx; tx_data[`DY]=sy; tx_data[`SX]=X; tx_data[`SY]=Y;
        tx_data[`OP]=writing?`WR_RESP:`RD_RESP;
        tx_data[`TAG]=tag; tx_data[`RESP]=resp; tx_data[`DATA]=result;
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=RX_HEADER; addr<=0; data<=0; result<=0; strb<=0;
            sx<=0; sy<=0; resp<=0; tag<=0; writing<=0; aw_done<=0; w_done<=0; ar_done<=0;
        end else case(state)
            RX_HEADER: if(rx_valid) begin
                addr<=rx_data[`DATA]; sx<=rx_data[`SX]; sy<=rx_data[`SY];
                tag<=rx_data[`TAG]; strb<=rx_data[`STRB]; writing<=rx_data[`OP]==`WR_REQ;
                aw_done<=0; w_done<=0; ar_done<=0;
                state <= (rx_data[`OP]==`WR_REQ) ? RX_BODY : READ;
            end
            RX_BODY: if(rx_valid) begin data<=rx_data[`DATA]; state<=WRITE; end
            WRITE: begin
                if(m_awvalid && m_awready) aw_done<=1;
                if(m_wvalid && m_wready) w_done<=1;
                if(m_bvalid && m_bready) begin resp<=m_bresp; result<=0; state<=TX; end
            end
            READ: begin
                if(m_arvalid && m_arready) ar_done<=1;
                if(m_rvalid && m_rready) begin resp<=m_rresp; result<=m_rdata; state<=TX; end
            end
            TX: if(tx_ready) state<=RX_HEADER;
            default: state<=RX_HEADER;
        endcase
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst && rx_valid && rx_ready) begin
        if(state==RX_HEADER && (!rx_data[`HEAD] ||
           !(rx_data[`OP]==`RD_REQ || rx_data[`OP]==`WR_REQ))) $fatal(1,"Bad request header");
        if(state==RX_BODY && (rx_data[`HEAD] || !rx_data[`TAIL])) $fatal(1,"Bad write tail");
    end
`endif
endmodule
