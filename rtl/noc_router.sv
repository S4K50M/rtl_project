`include "noc_defs.vh"
module noc_router #(parameter X=0,Y=0,DEPTH=4,FAST=0,MINIMIZED=0,ALLOW_MIXED=0)(
    input wire clk,rst,
    input wire [5*64-1:0] in_flit,
    input wire [4:0] in_valid,
    output wire [4:0] in_credit,
    output reg [5*64-1:0] out_flit,
    output reg [4:0] out_valid,
    input wire [4:0] out_credit
);
    localparam IDLE=0,ROUTE=1,ACTIVE=2,WAIT_CREDIT=3;
    wire [63:0] front [0:4];
    wire [4:0] empty,full;
    wire [2:0] decoded [0:4];
    wire [2:0] decoded_xy [0:4];
    wire [$clog2(DEPTH+1)-1:0] occupancy [0:4];
    reg [4:0] pop;
    reg [1:0] state [0:4];
    reg [2:0] route [0:4];
    reg [2:0] owner [0:4];
    reg [4:0] locked;
    reg [$clog2(DEPTH+1)-1:0] credits [0:4];
    wire [4:0] request [0:4];
    wire [4:0] grant [0:4];
    reg [2:0] chosen [0:4];
    assign in_credit=pop;
    genvar g,j;
    generate for(g=0;g<5;g=g+1) begin: ports
        noc_fifo #(.DEPTH(DEPTH)) fifo(clk,rst,in_valid[g],pop[g],in_flit[g*64+:64],front[g],empty[g],full[g],occupancy[g]);
        xy_route #(.X(X),.Y(Y),.MINIMIZED(MINIMIZED)) rc(front[g][`DX],front[g][`DY],decoded_xy[g]);
        // Deliberately unsafe experiment: per-packet YX mixed with XY allows
        // every turn. Bit 36 is ignored in all production configurations.
        assign decoded[g]=(ALLOW_MIXED && front[g][36]) ?
            (front[g][`DY]>Y ? 3'd3 : front[g][`DY]<Y ? 3'd4 :
             front[g][`DX]>X ? 3'd1 : front[g][`DX]<X ? 3'd2 : 3'd0) : decoded_xy[g];
        rr_arbiter #(.MINIMIZED(MINIMIZED)) rr(clk,rst,out_valid[g],request[g],grant[g]);
        for(j=0;j<5;j=j+1) begin: requests
            assign request[g][j]=!empty[j] && (state[j]==ACTIVE || state[j]==WAIT_CREDIT) &&
                route[j]==g && (!locked[g] || owner[g]==j);
        end
    end endgenerate
    // Input selection is one-hot (one XY route, no virtual channels).
    // Output stage resolves contention; ownership persists through the tail.
    always @* begin
        pop=0; out_valid=0; out_flit=0;
        for(integer o=0;o<5;o=o+1) begin
            chosen[o]=0;
            for(integer i=0;i<5;i=i+1)
                if(grant[o][i] && credits[o]!=0) begin
                    chosen[o]=i;
                    out_valid[o]=!rst;
                    out_flit[o*64+:64]=front[i];
                    pop[i]=!rst;
                end
        end
    end
    integer i,o;
    always @(posedge clk) begin
        if(rst) begin
            locked<=0;
            for(i=0;i<5;i=i+1) begin state[i]<=IDLE; route[i]<=0; owner[i]<=0; credits[i]<=DEPTH; end
        end else begin
            for(o=0;o<5;o=o+1) begin
                case({out_credit[o],out_valid[o]})
                    2'b10: credits[o]<=credits[o]+1'b1;
                    2'b01: credits[o]<=credits[o]-1'b1;
                    default: ;
                endcase
                if(out_valid[o]) begin
                    owner[o]<=chosen[o];
                    locked[o]<=!out_flit[o*64+`TAIL];
                end
            end
            for(i=0;i<5;i=i+1) begin
                case(state[i])
                    IDLE: if(!empty[i]) begin
                        if(FAST) begin route[i]<=decoded[i]; state[i]<=ACTIVE; end
                        else state[i]<=ROUTE;
                    end
                    ROUTE: begin route[i]<=decoded[i]; state[i]<=ACTIVE; end
                    ACTIVE,WAIT_CREDIT: begin
                        if(pop[i] && front[i][`TAIL]) state[i]<=IDLE;
                        else if(credits[route[i]]==0) state[i]<=WAIT_CREDIT;
                        else state[i]<=ACTIVE;
                    end
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst) begin
        for(integer q=0;q<5;q=q+1) begin
            if(credits[q]>DEPTH) $fatal(1,"Credit out of bounds");
            if(out_valid[q] && credits[q]==0) $fatal(1,"No credit");
            if(state[q]==IDLE && !empty[q] && !front[q][`HEAD]) $fatal(1,"Expected header");
        end
    end
`endif
endmodule
