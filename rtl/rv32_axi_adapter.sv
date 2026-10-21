module rv32_axi_adapter(
    input wire clk,rst,
    input wire req_valid,output wire req_ready,input wire req_write,
    input wire [31:0] req_addr,req_wdata,input wire [3:0] req_wstrb,
    output wire rsp_valid,input wire rsp_ready,output reg [31:0] rsp_data,output reg rsp_error,
    output wire [31:0] awaddr,output wire awvalid,input wire awready,
    output wire [31:0] wdata,output wire [3:0] wstrb,output wire wvalid,input wire wready,
    input wire [1:0] bresp,input wire bvalid,output wire bready,
    output wire [31:0] araddr,output wire arvalid,input wire arready,
    input wire [31:0] rdata,input wire [1:0] rresp,input wire rvalid,output wire rready
);
    localparam IDLE=0,WRITE=1,READ=2,RESPONSE=3;
    reg [1:0] state;
    reg [31:0] addr,data;
    reg [3:0] strb;
    reg aw_done,w_done,ar_done;
    assign req_ready=state==IDLE && !rst;
    assign rsp_valid=state==RESPONSE;
    assign awaddr=addr; assign araddr=addr; assign wdata=data; assign wstrb=strb;
    assign awvalid=state==WRITE && !aw_done;
    assign wvalid=state==WRITE && !w_done;
    assign bready=state==WRITE && aw_done && w_done;
    assign arvalid=state==READ && !ar_done;
    assign rready=state==READ && ar_done;
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; addr<=0; data<=0; strb<=0; aw_done<=0; w_done<=0; ar_done<=0;
            rsp_data<=0; rsp_error<=0;
        end else case(state)
            IDLE: if(req_valid) begin
                addr<=req_addr; data<=req_wdata; strb<=req_wstrb; aw_done<=0; w_done<=0; ar_done<=0;
                state<=req_write?WRITE:READ;
            end
            WRITE: begin
                if(awvalid && awready) aw_done<=1;
                if(wvalid && wready) w_done<=1;
                if(bvalid && bready) begin rsp_data<=0; rsp_error<=bresp!=0; state<=RESPONSE; end
            end
            READ: begin
                if(arvalid && arready) ar_done<=1;
                if(rvalid && rready) begin rsp_data<=rdata; rsp_error<=rresp!=0; state<=RESPONSE; end
            end
            RESPONSE: if(rsp_ready) state<=IDLE;
        endcase
    end
endmodule
