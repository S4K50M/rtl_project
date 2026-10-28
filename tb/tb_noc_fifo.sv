// =============================================================================
// tb_noc_fifo.sv — Functional testbench for noc_fifo
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   clk, rst, push, pop, din, dout, empty, full, count
//   DUT internal: mem[], rd, wr  (useful for wrap-around verification)
// WHAT TO LOOK FOR:
//   • 'count' increments on push, decrements on pop, stays same on both.
//   • 'full' asserts when count==DEPTH, 'empty' when count==0.
//   • 'dout' changes to next entry one cycle after pop.
//   • On simultaneous push+pop, count should stay constant.
// SUCCESS: "$finish" is reached with "[RESULT] ALL TESTS PASSED" in transcript.
// =============================================================================

`timescale 1ns/1ps

module tb_noc_fifo;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam WIDTH = 64;
    localparam DEPTH = 4;
    localparam DEPTH3 = 3;          // non-power-of-two depth instance
    localparam CLK_HALF = 5;        // 10 ns period

    // -------------------------------------------------------------------------
    // DUT A  —  default DEPTH=4
    // -------------------------------------------------------------------------
    logic clk = 0, rst = 1;
    logic push_a, pop_a;
    logic [WIDTH-1:0] din_a;
    wire  [WIDTH-1:0] dout_a;
    wire  empty_a, full_a;
    wire  [$clog2(DEPTH+1)-1:0] count_a;

    noc_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut_a (
        .clk(clk), .rst(rst),
        .push(push_a), .pop(pop_a),
        .din(din_a), .dout(dout_a),
        .empty(empty_a), .full(full_a),
        .count(count_a)
    );

    // -------------------------------------------------------------------------
    // DUT B  —  DEPTH=3  (non-power-of-two)
    // -------------------------------------------------------------------------
    logic push_b, pop_b;
    logic [WIDTH-1:0] din_b;
    wire  [WIDTH-1:0] dout_b;
    wire  empty_b, full_b;
    wire  [$clog2(DEPTH3+1)-1:0] count_b;

    noc_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH3)) dut_b (
        .clk(clk), .rst(rst),
        .push(push_b), .pop(pop_b),
        .din(din_b), .dout(dout_b),
        .empty(empty_b), .full(full_b),
        .count(count_b)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    always #CLK_HALF clk = ~clk;

    // -------------------------------------------------------------------------
    // Reference scoreboard (SystemVerilog queue)
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] ref_q[$];

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string tag, input logic cond);
        if (!cond) begin
            $display("[FAIL] %s  at time %0t", tag, $time);
            fail_count++;
        end
    endtask

    task automatic do_push_a(input [WIDTH-1:0] val);
        @(negedge clk);
        push_a = 1; din_a = val; pop_a = 0;
        @(posedge clk); #1;
        ref_q.push_back(val);
        push_a = 0;
    endtask

    task automatic do_pop_a();
        @(negedge clk);
        pop_a = 1; push_a = 0;
        @(posedge clk); #1;
        // dout_a is the head that was just read; pointer advances next cycle
        void'(ref_q.pop_front());
        pop_a = 0;
    endtask

    task automatic check_dout_a(input string tag);
        // After a pop, one cycle later the read pointer has advanced
        @(negedge clk); // let combinational settle
        if (ref_q.size() > 0)
            check(tag, dout_a === ref_q[0]);
        // If queue empty, dout is don't-care
    endtask

    // =========================================================================
    // Main test body
    // =========================================================================
    integer i, j;
    logic [WIDTH-1:0] rng_state;

    // Simulation timeout watchdog
    initial begin
        #500000;
        $fatal(1, "[TIMEOUT] tb_noc_fifo exceeded simulation limit");
    end

    initial begin
        // Initialise drive signals
        push_a = 0; pop_a = 0; din_a = 0;
        push_b = 0; pop_b = 0; din_b = 0;
        rng_state = 64'hA5A5_1234_BEEF_CAFE;

        // =================================================================
        // TEST 1: Reset
        // =================================================================
        $display("[TEST] Reset verification");
        rst = 1;
        repeat(4) @(negedge clk);
        @(posedge clk); #1;
        check("reset empty_a=1",  empty_a === 1'b1);
        check("reset full_a=0",   full_a  === 1'b0);
        check("reset count_a=0",  count_a === '0);
        check("reset empty_b=1",  empty_b === 1'b1);
        check("reset full_b=0",   full_b  === 1'b0);
        check("reset count_b=0",  count_b === '0);
        rst = 0; ref_q = {};
        @(negedge clk);
        $display("[PASS] Reset verification");
        pass_count++;

        // =================================================================
        // TEST 2: Single push, check count and not-empty
        // =================================================================
        $display("[TEST] Single push");
        @(negedge clk);
        push_a = 1; din_a = 64'hDEAD_BEEF_0000_0001; pop_a = 0;
        @(posedge clk); #1;
        ref_q.push_back(64'hDEAD_BEEF_0000_0001);
        push_a = 0;
        @(negedge clk);
        check("single push count=1",  count_a === 1);
        check("single push empty=0",  empty_a === 0);
        check("single push full=0",   full_a  === 0);
        check("single push dout",     dout_a  === ref_q[0]);
        $display("[PASS] Single push");
        pass_count++;

        // =================================================================
        // TEST 3: Single pop
        // =================================================================
        $display("[TEST] Single pop");
        @(negedge clk);
        pop_a = 1; push_a = 0;
        @(posedge clk); #1;
        void'(ref_q.pop_front());
        pop_a = 0;
        @(negedge clk);
        check("single pop count=0", count_a === 0);
        check("single pop empty=1", empty_a === 1);
        $display("[PASS] Single pop");
        pass_count++;

        // =================================================================
        // TEST 4: Fill FIFO completely
        // =================================================================
        $display("[TEST] Fill FIFO (DEPTH=%0d)", DEPTH);
        ref_q = {};
        for (i = 0; i < DEPTH; i++) begin
            @(negedge clk);
            push_a = 1; din_a = 64'hC0FFEE00 + i; pop_a = 0;
            @(posedge clk); #1;
            ref_q.push_back(64'hC0FFEE00 + i);
            push_a = 0;
        end
        @(negedge clk);
        check("full flag set",     full_a  === 1);
        check("empty flag clear",  empty_a === 0);
        check("count == DEPTH",    count_a === DEPTH);
        $display("[PASS] Fill FIFO");
        pass_count++;

        // =================================================================
        // TEST 5: Drain FIFO completely, check ordering
        // =================================================================
        $display("[TEST] Drain FIFO (ordering check)");
        for (i = 0; i < DEPTH; i++) begin
            logic [WIDTH-1:0] expected_val;
            expected_val = ref_q[0];
            check({$sformatf("drain[%0d] dout", i)}, dout_a === expected_val);
            @(negedge clk);
            pop_a = 1; push_a = 0;
            @(posedge clk); #1;
            void'(ref_q.pop_front());
            pop_a = 0;
        end
        @(negedge clk);
        check("after drain count=0", count_a === 0);
        check("after drain empty=1", empty_a === 1);
        $display("[PASS] Drain FIFO ordering");
        pass_count++;

        // =================================================================
        // TEST 6: Simultaneous push + pop (count must stay constant)
        // =================================================================
        $display("[TEST] Simultaneous push and pop");
        // push one first so the FIFO is not empty
        @(negedge clk);
        push_a = 1; din_a = 64'hAAAA_0001; pop_a = 0;
        @(posedge clk); #1;
        ref_q.push_back(64'hAAAA_0001);
        push_a = 0;
        @(negedge clk);
        // now do simultaneous push+pop for 6 cycles
        for (i = 0; i < 6; i++) begin
            logic [WIDTH-1:0] new_val;
            new_val = 64'hAAAA_0002 + i;
            @(negedge clk);
            push_a = 1; din_a = new_val; pop_a = 1;
            @(posedge clk); #1;
            ref_q.push_back(new_val);
            void'(ref_q.pop_front());
            push_a = 0; pop_a = 0;
            @(negedge clk);
            check($sformatf("simult[%0d] count stable", i), count_a === ref_q.size());
        end
        // drain remaining
        while (ref_q.size() > 0) begin
            @(negedge clk); pop_a = 1;
            @(posedge clk); #1;
            void'(ref_q.pop_front());
            pop_a = 0;
        end
        @(negedge clk);
        check("simult drain empty", empty_a === 1);
        $display("[PASS] Simultaneous push and pop");
        pass_count++;

        // =================================================================
        // TEST 7: Wrap-around (push DEPTH+2 values total with interleaved pops)
        // =================================================================
        $display("[TEST] Wrap-around pointer");
        ref_q = {};
        // Fill to DEPTH-1
        for (i = 0; i < DEPTH-1; i++) begin
            @(negedge clk); push_a=1; din_a=64'hBBBB_0000+i; pop_a=0;
            @(posedge clk); #1; ref_q.push_back(64'hBBBB_0000+i); push_a=0;
        end
        // Pop 2
        for (i = 0; i < 2; i++) begin
            @(negedge clk); pop_a=1; push_a=0;
            @(posedge clk); #1; void'(ref_q.pop_front()); pop_a=0;
        end
        // Push DEPTH-1 more — wraps write pointer without exceeding capacity
        for (i = 0; i < DEPTH-1; i++) begin
            @(negedge clk); push_a=1; din_a=64'hCCCC_0000+i; pop_a=0;
            @(posedge clk); #1; ref_q.push_back(64'hCCCC_0000+i); push_a=0;
        end
        // Drain and verify order
        while (ref_q.size() > 0) begin
            logic [WIDTH-1:0] exp;
            exp = ref_q[0];
            check("wrap dout", dout_a === exp);
            @(negedge clk); pop_a=1; push_a=0;
            @(posedge clk); #1; void'(ref_q.pop_front()); pop_a=0;
        end
        @(negedge clk);
        check("wrap empty at end", empty_a === 1);
        $display("[PASS] Wrap-around pointer");
        pass_count++;

        // =================================================================
        // TEST 8: Randomised legal push/pop sequences
        // =================================================================
        $display("[TEST] Randomised legal push/pop sequences");
        ref_q = {};
        for (i = 0; i < 200; i++) begin
            logic do_push_r, do_pop_r;
            // LCG PRNG
            rng_state = rng_state * 64'h6C62272E07BB0142 + 64'h62B821756295C58D;
            do_push_r = (rng_state[3:0] < 10) && !full_a;
            do_pop_r  = (rng_state[7:4] < 8)  && !empty_a;
            @(negedge clk);
            push_a = do_push_r;
            pop_a  = do_pop_r;
            din_a  = rng_state[63:0];
            @(posedge clk); #1;
            if (do_push_r) ref_q.push_back(rng_state[63:0]);
            if (do_pop_r)  void'(ref_q.pop_front());
            push_a = 0; pop_a = 0;
            @(negedge clk);
            check($sformatf("rand[%0d] count", i), count_a === ref_q.size());
            check($sformatf("rand[%0d] empty", i), empty_a === (ref_q.size() == 0));
            check($sformatf("rand[%0d] full",  i), full_a  === (ref_q.size() == DEPTH));
            if (!empty_a)
                check($sformatf("rand[%0d] dout", i), dout_a === ref_q[0]);
        end
        // drain leftover
        while (!empty_a) begin
            logic [WIDTH-1:0] exp;
            exp = ref_q[0];
            check("rand drain dout", dout_a === exp);
            @(negedge clk); pop_a=1;
            @(posedge clk); #1; void'(ref_q.pop_front()); pop_a=0;
        end
        $display("[PASS] Randomised push/pop sequences");
        pass_count++;

        // =================================================================
        // TEST 9: DEPTH=3 (non-power-of-two) basic fill/drain
        // =================================================================
        $display("[TEST] DEPTH=3 fill and drain");
        rst = 1; repeat(3) @(negedge clk); rst = 0;
        @(negedge clk);
        for (i = 0; i < DEPTH3; i++) begin
            @(negedge clk); push_b=1; din_b=64'hD3D3_0000+i; pop_b=0;
            @(posedge clk); #1; push_b=0;
        end
        @(negedge clk);
        check("d3 full",  full_b  === 1);
        check("d3 count", count_b === DEPTH3);
        for (i = 0; i < DEPTH3; i++) begin
            check($sformatf("d3 dout[%0d]", i), dout_b === (64'hD3D3_0000+i));
            @(negedge clk); pop_b=1; push_b=0;
            @(posedge clk); #1; pop_b=0;
        end
        @(negedge clk);
        check("d3 empty after drain", empty_b === 1);
        $display("[PASS] DEPTH=3 fill and drain");
        pass_count++;

        // =================================================================
        // RESULTS
        // =================================================================
        if (fail_count == 0)
            $display("[RESULT] tb_noc_fifo: ALL %0d TESTS PASSED", pass_count);
        else begin
            $display("[RESULT] tb_noc_fifo: %0d PASSED, %0d FAILED", pass_count, fail_count);
            $fatal(1, "tb_noc_fifo FAILED");
        end
        $finish;
    end

endmodule
