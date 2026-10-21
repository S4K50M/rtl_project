module noc_mesh #(parameter NX=2,NY=2,DEPTH=4,FAST=0,MINIMIZED=0,ALLOW_MIXED=0)(
    input wire clk,rst,
    input wire [NX*NY*64-1:0] inject_flit,
    input wire [NX*NY-1:0] inject_valid,
    output wire [NX*NY-1:0] inject_credit,
    output wire [NX*NY*64-1:0] eject_flit,
    output wire [NX*NY-1:0] eject_valid,
    input wire [NX*NY-1:0] eject_credit
);
    wire [319:0] ri [0:NX*NY-1],ro [0:NX*NY-1];
    wire [4:0] rv [0:NX*NY-1],ov [0:NX*NY-1],rc [0:NX*NY-1],oc [0:NX*NY-1];
    genvar x,y;
    generate for(y=0;y<NY;y=y+1) begin: rows
        for(x=0;x<NX;x=x+1) begin: cols
            localparam N=y*NX+x;
            noc_router #(.X(x),.Y(y),.DEPTH(DEPTH),.FAST(FAST),.MINIMIZED(MINIMIZED),.ALLOW_MIXED(ALLOW_MIXED)) router(clk,rst,ri[N],rv[N],rc[N],ro[N],ov[N],oc[N]);
            assign ri[N][0+:64]=inject_flit[N*64+:64];
            assign rv[N][0]=inject_valid[N];
            assign inject_credit[N]=rc[N][0];
            assign eject_flit[N*64+:64]=ro[N][0+:64];
            assign eject_valid[N]=ov[N][0];
            assign oc[N][0]=eject_credit[N];
            if(x<NX-1) begin
                assign ri[N][64+:64]=ro[N+1][128+:64]; assign rv[N][1]=ov[N+1][2]; assign oc[N][1]=rc[N+1][2];
            end else begin assign ri[N][64+:64]=0; assign rv[N][1]=0; assign oc[N][1]=0; end
            if(x>0) begin
                assign ri[N][128+:64]=ro[N-1][64+:64]; assign rv[N][2]=ov[N-1][1]; assign oc[N][2]=rc[N-1][1];
            end else begin assign ri[N][128+:64]=0; assign rv[N][2]=0; assign oc[N][2]=0; end
            if(y<NY-1) begin
                assign ri[N][192+:64]=ro[N+NX][256+:64]; assign rv[N][3]=ov[N+NX][4]; assign oc[N][3]=rc[N+NX][4];
            end else begin assign ri[N][192+:64]=0; assign rv[N][3]=0; assign oc[N][3]=0; end
            if(y>0) begin
                assign ri[N][256+:64]=ro[N-NX][192+:64]; assign rv[N][4]=ov[N-NX][3]; assign oc[N][4]=rc[N-NX][3];
            end else begin assign ri[N][256+:64]=0; assign rv[N][4]=0; assign oc[N][4]=0; end
        end
    end endgenerate
endmodule
