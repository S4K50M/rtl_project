`include "noc_defs.vh"
// A bounded outstanding synthetic AXI read client at a non-CPU node.
// Its responses are drained independently from the request mesh.
module traffic_client #(parameter NODE=2)(
    input wire clk,rst,enable,hotspot,input wire [15:0] rate,
    output reg [63:0] tx_data,output wire tx_valid,input wire tx_ready,
    input wire [63:0] rx_data,input wire rx_valid,output wire rx_ready,
    output reg [31:0] injected,delivered,errors,
    output wire [31:0] mean_q16,variance_q16
);
    reg [1:0] state;
    reg [31:0] rng,ticks,start;
    reg [1:0] dest;
    reg [7:0] tag;
    reg sample;
    reg [31:0] latency;
    wire [31:0] count;
    wire stats_ready;
    assign tx_valid=state==1;
    assign rx_ready=state==2 && stats_ready;
    always @* begin
        tx_data=0; tx_data[`HEAD]=1; tx_data[`TAIL]=1;
        tx_data[`DX]=dest==2?0:1; tx_data[`DY]=dest==1?0:1;
        tx_data[`SX]=NODE%2; tx_data[`SY]=NODE/2;
        tx_data[`TAG]=tag; tx_data[`OP]=`RD_REQ;
        tx_data[`DATA]=dest==1?32'h3000:dest==2?32'h10000004:32'h20000000;
    end
    welford_stats stats(clk,rst,sample,latency,count,mean_q16,variance_q16,stats_ready);
    always @(posedge clk) begin
        if(rst) begin
            state<=0; rng<=32'h73a59101+NODE; ticks<=0; start<=0; tag<=0;
            injected<=0; delivered<=0; errors<=0; sample<=0; latency<=0; dest<=1;
        end else begin
            ticks<=ticks+1'b1; sample<=0;
            rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            case(state)
                0: if(enable && rng[15:0]<rate && (hotspot || rng[17:16]!=3)) begin
                    dest<=hotspot?1:rng[17:16]+1'b1; state<=1;
                end
                1: if(tx_ready) begin injected<=injected+1'b1; start<=ticks; state<=2; end
                2: if(rx_valid && rx_ready) begin
                    delivered<=delivered+1'b1; sample<=1; latency<=ticks-start; tag<=tag+1'b1; state<=0;
                    if(rx_data[`TAG]!=tag || rx_data[`RESP]!=0 || rx_data[`OP]!=`RD_RESP) errors<=errors+1'b1;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
