// Pipelined Welford Statistics Engine
 // Q16.16 mean, M2, and population variance.
 // Two iterative 64-cycle divisions share one divider.
 // Intermediate arithmetic is registered to improve FPGA timing.
 //
 // Target: Zybo Z7-10 (xc7z010clg400-1), 125 MHz.

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

    // FSM states
    localparam [2:0]
        IDLE          = 3'd0,
        MEAN_WAIT     = 3'd1,
        DELTA2_STAGE  = 3'd2,
        MULT_STAGE    = 3'd3,
        M2_STAGE      = 3'd4,
        VAR_WAIT      = 3'd5;

    reg [2:0] state;

    // Welford registers
    reg signed [63:0] mean_acc;
    reg signed [63:0] delta;
    reg signed [63:0] sample_x;

    reg [63:0] m2;
    reg [63:0] numerator;
    reg [31:0] denominator;

    // Pipeline registers
    reg signed [63:0] delta2_q;
    reg signed [63:0] product_q;

    // Divider interface
    reg         div_start;
    wire        busy;
    wire        div_done;
    wire [63:0] quotient;

    // Clamp input latency to 32767 cycles.
    wire signed [63:0] x =
        $signed({
            1'b0,
            (latency > 32767 ?
                31'd32767 : latency[30:0]),
            16'b0
        });

    // Difference from current mean
    wire signed [63:0] input_delta =
        x - mean_acc;

    // Updated mean after first division
    wire signed [63:0] next_mean =
        mean_acc +
        (delta < 0 ?
            -$signed(quotient) :
             $signed(quotient));

    // Keep the original 64-bit product truncation.
    wire signed [63:0] increment =
        product_q >>> 16;

    // Updated M2
    wire [63:0] next_m2 =
        m2 + increment;

    // Ready/valid behavior preserved
    assign ready = (state == IDLE) && !rst;

    // Shared iterative divider
    unsigned_divider divide (
        .clk(clk),
        .rst(rst),
        .start(div_start),
        .numerator(numerator),
        .denominator(denominator),
        .busy(busy),
        .done(div_done),
        .quotient(quotient)
    );

    // Main state machine
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
            product_q    <= 0;

            numerator    <= 0;
            denominator  <= 1;
            div_start    <= 0;

        end else begin

            // Divider start is a one-cycle pulse.
            div_start <= 0;

            case (state)

                // ---------------------------------
                // Stage 0: Accept input
                // ---------------------------------
                IDLE: begin
                    if (valid && count < MAX_SAMPLES) begin

                        sample_x <= x;
                        delta    <= input_delta;

                        numerator <=
                            input_delta < 0 ?
                            -input_delta :
                             input_delta;

                        denominator <= count + 1'b1;

                        div_start <= 1'b1;
                        state <= MEAN_WAIT;
                    end
                end

                // ---------------------------------
                // Stage 1: Finish mean division
                // ---------------------------------
                MEAN_WAIT: begin
                    if (div_done) begin

                        mean_acc <= next_mean;

                        state <= DELTA2_STAGE;
                    end
                end

                // ---------------------------------
                // Stage 2: Calculate delta2
                // ---------------------------------
                DELTA2_STAGE: begin

                    delta2_q <= sample_x - mean_acc;

                    state <= MULT_STAGE;
                end

                // ---------------------------------
                // Stage 3: Registered multiplication
                // ---------------------------------
                MULT_STAGE: begin

                    product_q <= delta * delta2_q;

                    state <= M2_STAGE;
                end

                // ---------------------------------
                // Stage 4: Accumulate M2
                // ---------------------------------
                M2_STAGE: begin

                    m2 <= next_m2;

                    numerator <= next_m2;

                    div_start <= 1'b1;

                    state <= VAR_WAIT;
                end

                // ---------------------------------
                // Stage 5: Finish variance division
                // ---------------------------------
                VAR_WAIT: begin
                    if (div_done) begin

                        count <= count + 1'b1;

                        mean_q16 <= mean_acc[31:0];

                        variance_q16 <=
                            (quotient > 64'hffffffff) ?
                            32'hffffffff :
                            quotient[31:0];

                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule