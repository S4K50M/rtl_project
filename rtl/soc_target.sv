// KIND: 1 = RAM (0x00000000), 2 = UART/stats (0x10000000), 3 = timer (0x20000000).
module soc_target #(parameter KIND=1,WORDS=4096,MEM_FILE="build/firmware.hex",CLK_HZ=50000000,BAUD=115200)(
    input wire clk,rst,
    input wire [31:0] awaddr,input wire awvalid,output wire awready,
    input wire [31:0] wdata,input wire [3:0] wstrb,input wire wvalid,output wire wready,
    output reg [1:0] bresp,output reg bvalid,input wire bready,
    input wire [31:0] araddr,input wire arvalid,output wire arready,
    output reg [31:0] rdata,output reg [1:0] rresp,output reg rvalid,input wire rready,
    input wire [31:0] stat_count,stat_mean_q16,stat_variance_q16,
    input wire [31:0] traffic_injected,traffic_delivered,traffic_mean,traffic_variance,traffic_errors,
    output reg traffic_enable,traffic_hotspot,output reg [15:0] traffic_rate,
    output wire uart,
    output reg uart_event,output reg [7:0] uart_byte,
    output reg done,output reg [31:0] exit_code
);
    reg [31:0] memory [0:WORDS-1];
    reg [31:0] saved_addr,saved_data,timer;
    reg [3:0] saved_strb;
    reg have_aw,have_w;
    wire uart_ready;
    wire mapped_write=(KIND==1 && saved_addr<WORDS*4) ||
                      (KIND==2 && (saved_addr==32'h10000000 || saved_addr==32'h10000020)) ||
                      (KIND==3 && saved_addr==32'h20000004);
    wire commit=have_aw && have_w && !bvalid &&
                (KIND!=2 || saved_addr!=32'h10000000 || !saved_strb[0] || uart_ready);
    wire send_uart=commit && KIND==2 && saved_addr==32'h10000000 && saved_strb[0];
    generate if(KIND==1) begin: ram_init
        integer j;
        initial begin
            for(j=0;j<WORDS;j=j+1) memory[j]=0;
            if(MEM_FILE!="") $readmemh(MEM_FILE,memory);
        end
    end endgenerate
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) serial(clk,rst,send_uart,saved_data[7:0],uart_ready,uart);
    assign awready=!have_aw && !bvalid && !rst;
    assign wready=!have_w && !bvalid && !rst;
    assign arready=!rvalid && !rst;
    always @(posedge clk) begin
        if(rst) begin
            have_aw<=0; have_w<=0; bvalid<=0; rvalid<=0; bresp<=0; rresp<=0; rdata<=0;
            saved_addr<=0; saved_data<=0; saved_strb<=0; timer<=0;
            done<=0; exit_code<=0; uart_event<=0; uart_byte<=0;
            traffic_enable<=0; traffic_hotspot<=0; traffic_rate<=0;
        end else begin
            timer<=timer+1'b1; uart_event<=send_uart;
            if(send_uart) uart_byte<=saved_data[7:0];
            if(bvalid && bready) bvalid<=0;
            if(rvalid && rready) rvalid<=0;
            if(awvalid && awready) begin saved_addr<=awaddr; have_aw<=1; end
            if(wvalid && wready) begin saved_data<=wdata; saved_strb<=wstrb; have_w<=1; end
            if(commit) begin
                have_aw<=0; have_w<=0; bvalid<=1;
                bresp<=mapped_write && saved_addr[1:0]==0?2'b00:2'b11;
                if(mapped_write && saved_addr[1:0]==0) begin
                    if(KIND==1) for(integer b=0;b<4;b=b+1)
                        if(saved_strb[b]) memory[saved_addr[31:2]][b*8+:8]<=saved_data[b*8+:8];
                    if(KIND==3 && saved_strb==15) begin done<=1; exit_code<=saved_data; end
                    if(KIND==2 && saved_addr==32'h10000020) begin
                        if(saved_strb[0]) begin traffic_enable<=saved_data[0]; traffic_hotspot<=saved_data[1]; end
                        if(saved_strb[2]) traffic_rate[7:0]<=saved_data[23:16];
                        if(saved_strb[3]) traffic_rate[15:8]<=saved_data[31:24];
                    end
                end
            end
            if(arvalid && arready) begin
                rvalid<=1; rresp<=0; rdata<=0;
                if(araddr[1:0]!=0) rresp<=3;
                else if(KIND==1 && araddr<WORDS*4) rdata<=memory[araddr[31:2]];
                else if(KIND==2 && araddr==32'h10000004) rdata<={31'b0,uart_ready};
                else if(KIND==2 && araddr==32'h10000010) rdata<=stat_count;
                else if(KIND==2 && araddr==32'h10000014) rdata<=stat_mean_q16;
                else if(KIND==2 && araddr==32'h10000018) rdata<=stat_variance_q16;
                else if(KIND==2 && araddr==32'h10000020) rdata<={traffic_rate,14'b0,traffic_hotspot,traffic_enable};
                else if(KIND==2 && araddr==32'h10000024) rdata<=traffic_injected;
                else if(KIND==2 && araddr==32'h10000028) rdata<=traffic_delivered;
                else if(KIND==2 && araddr==32'h1000002c) rdata<=traffic_mean;
                else if(KIND==2 && araddr==32'h10000030) rdata<=traffic_variance;
                else if(KIND==2 && araddr==32'h10000034) rdata<=traffic_errors;
                else if(KIND==3 && araddr==32'h20000000) rdata<=timer;
                else rresp<=3;
            end
        end
    end
endmodule
