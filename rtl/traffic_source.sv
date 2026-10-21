`include "noc_defs.vh"
// Standalone hardware traffic source for direct mesh experiments.
// rate is a Bernoulli threshold / 65536 per idle cycle, not flits/cycle.
// Uniform destinations use rejection sampling (no modulo bias).
module traffic_source #(parameter NODE=0,NX=2,NY=2,SEED=32'h1)(
    input wire clk,rst,enable,hotspot,
    input wire [15:0] rate,
    output reg [63:0] data,output wire valid,input wire ready,
    output reg [31:0] packets_injected
);
    localparam N=NX*NY;
    reg [31:0] random_state;
    reg active;
    reg [1:0] flit_index;
    reg [3:0] dst;
    reg [31:0] ident;
    wire [3:0] candidate=random_state[19:16];
    assign valid=active;
    always @* begin
        data=0;
        data[`HEAD]=flit_index==0;
        data[`TAIL]=flit_index==2;
        if(flit_index==0) begin
            data[`DX]=dst%NX; data[`DY]=dst/NX;
            data[`SX]=NODE%NX; data[`SY]=NODE/NX;
        end
        data[`DATA]={ident[23:0],6'b0,flit_index};
    end
    always @(posedge clk) begin
        if(rst) begin random_state<=SEED==0?1:SEED; active<=0; flit_index<=0; dst<=0; ident<=0; packets_injected<=0; end
        else begin
            random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(!active && enable && random_state[15:0]<rate && candidate<N && candidate!=NODE) begin
                dst<=(hotspot && NODE!=0 && random_state[23:20]<13)?0:candidate;
                active<=1; flit_index<=0;
            end
            if(active && ready) begin
                if(flit_index==2) begin active<=0; ident<=ident+1'b1; packets_injected<=packets_injected+1'b1; end
                else flit_index<=flit_index+1'b1;
            end
        end
    end
endmodule
