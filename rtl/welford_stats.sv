// Hand scheduled fixed-point HLS counterpart of hls/welford.cpp.
// Q16.16 mean and M2, population variance. Ready/valid input; two 64-cycle
// iterative divisions share hardware. Outputs commit atomically. Saturate
// sample count and variance; clamp input latency to 32767 cycles.
module welford_stats #(parameter MAX_SAMPLES=65535)(
    input wire clk,rst,valid,
    input wire [31:0] latency,
    output reg [31:0] count,mean_q16,variance_q16,
    output wire ready
);
    localparam IDLE=0,MEAN_WAIT=1,VAR_WAIT=2;
    reg [1:0] state;
    reg signed [63:0] mean_acc,delta,sample_x;
    reg [63:0] m2,numerator;
    reg [31:0] denominator;
    reg div_start;
    wire busy,div_done;
    wire [63:0] quotient;
    wire signed [63:0] x=$signed({1'b0,(latency>32767?31'd32767:latency[30:0]),16'b0});
    wire signed [63:0] input_delta=x-mean_acc;
    wire signed [63:0] next_mean=mean_acc+(delta<0 ? -$signed(quotient) : $signed(quotient));
    wire signed [63:0] delta2=sample_x-next_mean;
    wire signed [63:0] increment=(delta*delta2) >>> 16;
    wire [63:0] next_m2=m2+increment;
    assign ready=state==IDLE && !rst;
    unsigned_divider divide(clk,rst,div_start,numerator,denominator,busy,div_done,quotient);
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; count<=0; mean_acc<=0; mean_q16<=0; variance_q16<=0; m2<=0;
            sample_x<=0; delta<=0; div_start<=0; numerator<=0; denominator<=1;
        end else begin
            div_start<=0;
            case(state)
                IDLE: if(valid && count<MAX_SAMPLES) begin
                    sample_x<=x; delta<=input_delta;
                    numerator<=input_delta<0 ? -input_delta : input_delta;
                    denominator<=count+1'b1; div_start<=1; state<=MEAN_WAIT;
                end
                MEAN_WAIT: if(div_done) begin
                    mean_acc<=next_mean; m2<=next_m2;
                    numerator<=next_m2; div_start<=1; state<=VAR_WAIT;
                end
                VAR_WAIT: if(div_done) begin
                    count<=count+1'b1; mean_q16<=mean_acc[31:0];
                    variance_q16 <= (quotient>64'hffffffff) ? 32'hffffffff : quotient[31:0];
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
