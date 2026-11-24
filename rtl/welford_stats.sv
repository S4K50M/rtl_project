// Pipelined fixed-point Welford statistics engine.
// Q16.16 mean and M2; population variance; shared iterative divider.
// Registered 16-bit limb products replace the wide DSP cascade.
// Target: Zybo Z7-10, 125 MHz (timing closure must be verified).
module welford_stats #(
    parameter MAX_SAMPLES = 65535
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        valid,
    input  wire [31:0] latency,
    output reg  [31:0] count,
    output reg  [31:0] mean_q16,
    output reg  [31:0] variance_q16,
    output wire        ready
);
    localparam [2:0]
        IDLE         = 3'd0,
        MEAN_WAIT    = 3'd1,
        DELTA2_STAGE = 3'd2,
        MULT_STAGE   = 3'd3,
        CROSS_STAGE  = 3'd4,
        PROD_STAGE   = 3'd5,
        M2_STAGE     = 3'd6,
        VAR_WAIT     = 3'd7;

    reg [2:0] state;

    reg signed [63:0] mean_acc, sample_x;
    reg signed [31:0] delta, delta2_q;
    reg [63:0] m2, numerator;
    reg [31:0] denominator;

    reg div_start;
    wire busy, div_done;
    wire [63:0] quotient;

    // With 0 <= x, mean <= 32767 << 16, both signed differences
    // are representable in 32 bits. Keep other arithmetic at 64 bits.
    wire signed [63:0] x = $signed({1'b0,
        (latency > 32'd32767 ? 31'd32767 : latency[30:0]), 16'b0});
    wire signed [63:0] input_delta = x - mean_acc;
    wire signed [63:0] next_mean = mean_acc +
        (delta[31] ? -$signed(quotient) : $signed(quotient));
    wire signed [63:0] next_delta2 = sample_x - mean_acc;

    // Signed high limb, unsigned low limb (zero extended before
    // converting to signed). Each operand is at most 17 bits, so
    // a partial multiplication fits a single DSP48E1 multiplier.
    wire signed [16:0] a_lo = $signed({1'b0, delta[15:0]});
    wire signed [16:0] a_hi = $signed({delta[31], delta[31:16]});
    wire signed [16:0] b_lo = $signed({1'b0, delta2_q[15:0]});
    wire signed [16:0] b_hi = $signed({delta2_q[31], delta2_q[31:16]});

    // Registered partial products, with sufficient signed width.
    reg signed [33:0] p00, p01, p10, p11;
    reg signed [34:0] cross_q;
    reg [47:0] base_upper_q;
    reg [15:0] base_low_q;
    reg signed [63:0] product_q;

    // A*B = p00 + ((p01+p10)<<16) + (p11<<32).
    // Low 16 bits are unaffected by the shifted cross terms.
    // p00 fits unsigned 32 bits; p11 fits signed 32 bits.
    wire [47:0] cross_extended = {{13{cross_q[34]}}, cross_q};
    wire [47:0] product_upper = base_upper_q + cross_extended;

    wire signed [63:0] increment = product_q >>> 16;
    wire [63:0] next_m2 = m2 + increment;

    // Preserve existing saturation behavior: once the count reaches
    // MAX_SAMPLES, idle handshakes no longer update the statistics.
    assign ready = (state == IDLE) && !rst;

    // Positional mapping matches the original divider interface.
    unsigned_divider divide(clk, rst, div_start, numerator, denominator,
                            busy, div_done, quotient);

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            count        <= 0;
            mean_acc     <= 0;
            mean_q16     <= 0;
            variance_q16 <= 0;
            m2           <= 0;
            sample_x     <= 0;
            delta        <= 0;
            delta2_q     <= 0;
            p00          <= 0;
            p01          <= 0;
            p10          <= 0;
            p11          <= 0;
            cross_q      <= 0;
            base_upper_q <= 0;
            base_low_q   <= 0;
            product_q    <= 0;
            numerator    <= 0;
            denominator  <= 1;
            div_start    <= 0;
        end else begin
            div_start <= 0;
            case (state)
                IDLE: begin
                    if (valid && count < MAX_SAMPLES) begin
                        sample_x <= x;
                        delta <= input_delta[31:0];
                        numerator <= input_delta < 0 ? -input_delta : input_delta;
                        denominator <= count + 1'b1;
                        div_start <= 1'b1;
                        state <= MEAN_WAIT;
                    end
                end

                MEAN_WAIT: begin
                    if (div_done) begin
                        mean_acc <= next_mean;
                        state <= DELTA2_STAGE;
                    end
                end

                DELTA2_STAGE: begin
                    delta2_q <= next_delta2[31:0];
                    state <= MULT_STAGE;
                end

                // Four independent, registered limb multiplications.
                MULT_STAGE: begin
                    p00 <= a_lo * b_lo;
                    p01 <= a_lo * b_hi;
                    p10 <= a_hi * b_lo;
                    p11 <= a_hi * b_hi;
                    state <= CROSS_STAGE;
                end

                // Register cross-term sum independently of product sum.
                CROSS_STAGE: begin
                    cross_q <= $signed({p01[33], p01}) +
                               $signed({p10[33], p10});
                    base_upper_q <= {p11[31:0], p00[31:16]};
                    base_low_q <= p00[15:0];
                    state <= PROD_STAGE;
                end

                // Reconstruct the exact signed 64-bit product.
                PROD_STAGE: begin
                    product_q <= {product_upper, base_low_q};
                    state <= M2_STAGE;
                end

                M2_STAGE: begin
                    m2 <= next_m2;
                    numerator <= next_m2;
                    div_start <= 1'b1;
                    state <= VAR_WAIT;
                end

                VAR_WAIT: begin
                    if (div_done) begin
                        count <= count + 1'b1;
                        mean_q16 <= mean_acc[31:0];
                        variance_q16 <= (quotient > 64'hffffffff) ?
                                         32'hffffffff : quotient[31:0];
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
