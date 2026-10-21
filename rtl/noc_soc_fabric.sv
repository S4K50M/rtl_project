module noc_soc_fabric #(parameter FAST=0,MEM_FILE="build/firmware.hex",CLK_HZ=50000000,BAUD=115200)(
    input wire clk,rst,
    input wire [31:0] s_awaddr,input wire s_awvalid,output wire s_awready,
    input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
    output wire [1:0] s_bresp,output wire s_bvalid,input wire s_bready,
    input wire [31:0] s_araddr,input wire s_arvalid,output wire s_arready,
    output wire [31:0] s_rdata,output wire [1:0] s_rresp,output wire s_rvalid,input wire s_rready,
    output wire uart,uart_event,output wire [7:0] uart_byte,
    output wire done,output wire [31:0] exit_code,
    output wire [31:0] stat_count,stat_mean_q16,stat_variance_q16
);
    wire [255:0] req_if,req_ef,rsp_if,rsp_ef;
    wire [3:0] req_iv,req_ev,req_ic,req_ec,rsp_iv,rsp_ev,rsp_ic,rsp_ec;
    wire [63:0] req_tx [0:3],req_rx [0:3],rsp_tx [0:3],rsp_rx [0:3];
    wire [3:0] req_tv,req_tr,req_rv,req_rr,rsp_tv,rsp_tr,rsp_rv,rsp_rr;
    wire sample_valid,sample_ready; wire [31:0] sample_latency;
    wire traffic_enable,traffic_hotspot; wire [15:0] traffic_rate;
    wire [31:0] traffic_injected[1:3],traffic_delivered[1:3],traffic_mean[1:3],traffic_variance[1:3],traffic_errors[1:3];
    wire [31:0] injected_total=traffic_injected[1]+traffic_injected[2]+traffic_injected[3];
    wire [31:0] delivered_total=traffic_delivered[1]+traffic_delivered[2]+traffic_delivered[3];
    wire [31:0] errors_total=traffic_errors[1]+traffic_errors[2]+traffic_errors[3];
    noc_mesh #(.FAST(FAST)) requests(clk,rst,req_if,req_iv,req_ic,req_ef,req_ev,req_ec);
    noc_mesh #(.FAST(FAST)) responses(clk,rst,rsp_if,rsp_iv,rsp_ic,rsp_ef,rsp_ev,rsp_ec);
    genvar n;
    generate for(n=0;n<4;n=n+1) begin: nodes
        noc_endpoint req_ep(clk,rst,req_tx[n],req_tv[n],req_tr[n],req_rx[n],req_rv[n],req_rr[n],
            req_if[n*64+:64],req_iv[n],req_ic[n],req_ef[n*64+:64],req_ev[n],req_ec[n]);
        noc_endpoint rsp_ep(clk,rst,rsp_tx[n],rsp_tv[n],rsp_tr[n],rsp_rx[n],rsp_rv[n],rsp_rr[n],
            rsp_if[n*64+:64],rsp_iv[n],rsp_ic[n],rsp_ef[n*64+:64],rsp_ev[n],rsp_ec[n]);
        if(n==0) begin: cpu
            assign req_rr[n]=1;
            assign rsp_tx[n]=0; assign rsp_tv[n]=0;
        end else begin: peripheral
            wire [31:0] awaddr,wdata,araddr,rdata;
            wire [3:0] wstrb;
            wire awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
            wire [1:0] bresp,rresp;
            wire p_uart,p_event,p_done,p_enable,p_hotspot;
            wire [15:0] p_rate; wire [7:0] p_byte; wire [31:0] p_exit;
            traffic_client #(.NODE(n)) generator(clk,rst,traffic_enable,traffic_hotspot,traffic_rate,
                req_tx[n],req_tv[n],req_tr[n],rsp_rx[n],rsp_rv[n],rsp_rr[n],
                traffic_injected[n],traffic_delivered[n],traffic_errors[n],traffic_mean[n],traffic_variance[n]);
            axi_noc_target #(.X(n%2),.Y(n/2)) ni(clk,rst,req_rx[n],req_rv[n],req_rr[n],rsp_tx[n],rsp_tv[n],rsp_tr[n],
                awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
                araddr,arvalid,arready,rdata,rresp,rvalid,rready);
            soc_target #(.KIND(n),.MEM_FILE(MEM_FILE),.CLK_HZ(CLK_HZ),.BAUD(BAUD)) device(clk,rst,
                awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
                araddr,arvalid,arready,rdata,rresp,rvalid,rready,
                stat_count,stat_mean_q16,stat_variance_q16,
                injected_total,delivered_total,traffic_mean[2],traffic_variance[2],errors_total,
                p_enable,p_hotspot,p_rate,p_uart,p_event,p_byte,p_done,p_exit);
            if(n==2) begin
                assign uart=p_uart; assign uart_event=p_event; assign uart_byte=p_byte;
                assign traffic_enable=p_enable; assign traffic_hotspot=p_hotspot; assign traffic_rate=p_rate;
            end
            if(n==3) begin assign done=p_done; assign exit_code=p_exit; end
        end
    end endgenerate
    axi_noc_host host(clk,rst,s_awaddr,s_awvalid,s_awready,s_wdata,s_wstrb,s_wvalid,s_wready,
        s_bresp,s_bvalid,s_bready,s_araddr,s_arvalid,s_arready,s_rdata,s_rresp,s_rvalid,s_rready,
        req_tx[0],req_tv[0],req_tr[0],rsp_rx[0],rsp_rv[0],rsp_rr[0],sample_valid,sample_latency,sample_ready);
    welford_stats stats(clk,rst,sample_valid,sample_latency,stat_count,stat_mean_q16,stat_variance_q16,sample_ready);
endmodule
