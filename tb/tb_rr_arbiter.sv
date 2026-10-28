// =============================================================================
// tb_rr_arbiter.sv — Functional testbench for rr_arbiter
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   clk, rst, advance, request[4:0], grant[4:0]
//   DUT internal: next[$clog2(N)-1:0]
// WHAT TO LOOK FOR:
//   • grant is always one-hot or zero.
//   • 'next' advances one slot each time 'advance' pulses high.
//   • On reset, 'next' returns to 0 and 'grant' tracks lowest-indexed request.
//   • With all 5 ports requesting continuously, each gets service exactly once
//     per 5 advance-pulse cycle.
// SUCCESS: "[RESULT] tb_rr_arbiter: ALL TESTS PASSED" in transcript.
// =============================================================================

`timescale 1ns/1ps

module tb_rr_arbiter;

    // -------------------------------------------------------------------------
    // Clock and DUT wires  (N=5, behavioral)
    // -------------------------------------------------------------------------
    localparam N = 5;
    localparam CLK_HALF = 5;

    logic clk = 0;
    always #CLK_HALF clk = ~clk;

    // DUT A — behavioral (MINIMIZED=0)
    logic       rst_a, advance_a;
    logic [N-1:0] request_a;
    wire  [N-1:0] grant_a;

    rr_arbiter #(.N(N), .MINIMIZED(0)) dut_a (
        .clk(clk), .rst(rst_a), .advance(advance_a),
        .request(request_a), .grant(grant_a)
    );

    // DUT B — minimized (MINIMIZED=1, N=5)
    logic       rst_b, advance_b;
    logic [N-1:0] request_b;
    wire  [N-1:0] grant_b;

    rr_arbiter #(.N(N), .MINIMIZED(1)) dut_b (
        .clk(clk), .rst(rst_b), .advance(advance_b),
        .request(request_b), .grant(grant_b)
    );

    // -------------------------------------------------------------------------
    // Utilities
    // -------------------------------------------------------------------------
    int pass_count = 0, fail_count = 0;
    logic [N-1:0] service_count[N];   // per-port grant tallies

    task automatic check(input string tag, input logic cond);
        if (!cond) begin
            $display("[FAIL] %s  at time %0t", tag, $time);
            fail_count++;
        end
    endtask

    // Check one-hot property
    function automatic logic is_one_hot_or_zero(input [N-1:0] v);
        return (v & (v - 1'b1)) == 0;
    endfunction

    // Apply one arbitration beat: set request, pulse advance, capture grant
    task automatic arb_beat(
        input  [N-1:0] req,
        output [N-1:0] gnt
    );
        @(negedge clk);
        request_a = req;
        advance_a = 1;
        @(posedge clk); #1;
        gnt = grant_a;
        advance_a = 0;
    endtask

    // Reset DUT A
    task automatic do_reset_a();
        rst_a = 1; advance_a = 0; request_a = 0;
        repeat(3) @(negedge clk);
        rst_a = 0;
        @(negedge clk);
    endtask

    // Reset DUT B
    task automatic do_reset_b();
        rst_b = 1; advance_b = 0; request_b = 0;
        repeat(3) @(negedge clk);
        rst_b = 0;
        @(negedge clk);
    endtask

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #200000;
        $fatal(1, "[TIMEOUT] tb_rr_arbiter exceeded limit");
    end

    // =========================================================================
    // Main
    // =========================================================================
    integer i, j;
    logic [N-1:0] gnt;
    integer grant_idx;
    integer grant_hist[N];

    initial begin
        rst_a=1; rst_b=1; advance_a=0; advance_b=0;
        request_a=0; request_b=0;
        repeat(4) @(negedge clk);

        // =================================================================
        // TEST 1: Reset — grant must be zero after reset with no requests
        // =================================================================
        $display("[TEST] Reset behavior");
        do_reset_a();
        @(posedge clk); #1;
        check("reset grant==0", grant_a === 0);
        $display("[PASS] Reset behavior");
        pass_count++;

        // =================================================================
        // TEST 2: No request → no grant
        // =================================================================
        $display("[TEST] No request => no grant");
        @(negedge clk); request_a = 5'b00000; advance_a = 0;
        repeat(4) @(posedge clk); #1;
        check("no req no grant", grant_a === 0);
        $display("[PASS] No request => no grant");
        pass_count++;

        // =================================================================
        // TEST 3: Single-port requests
        // =================================================================
        $display("[TEST] Single port requests");
        for (i = 0; i < N; i++) begin
            do_reset_a();
            arb_beat(1 << i, gnt);
            check($sformatf("single[%0d] one-hot", i), is_one_hot_or_zero(gnt));
            check($sformatf("single[%0d] correct bit", i), gnt === (1 << i));
        end
        $display("[PASS] Single port requests");
        pass_count++;

        // =================================================================
        // TEST 4: Grant is subset of request
        // =================================================================
        $display("[TEST] grant is subset of request");
        do_reset_a();
        for (i = 0; i < 30; i++) begin
            automatic logic [N-1:0] req = $urandom_range(1, (1<<N)-1);
            arb_beat(req, gnt);
            check($sformatf("subset[%0d]", i), (gnt & ~req) === 0);
            check($sformatf("one-hot[%0d]", i), is_one_hot_or_zero(gnt));
            check($sformatf("nonzero[%0d]", i), gnt !== 0);
        end
        $display("[PASS] grant is subset of request");
        pass_count++;

        // =================================================================
        // TEST 5: Round-robin fairness with all ports requesting
        //         Over N consecutive beats each port must get exactly one grant
        // =================================================================
        $display("[TEST] Round-robin fairness (all ports active)");
        do_reset_a();
        for (j = 0; j < N; j++) grant_hist[j] = 0;
        for (i = 0; i < N*4; i++) begin
            arb_beat(5'b11111, gnt);
            for (j = 0; j < N; j++)
                if (gnt[j]) grant_hist[j]++;
        end
        // Each port should have been served exactly 4 times
        for (j = 0; j < N; j++)
            check($sformatf("fairness port %0d", j), grant_hist[j] === 4);
        $display("[PASS] Round-robin fairness");
        pass_count++;

        // =================================================================
        // TEST 6: advance=0 must NOT advance priority pointer
        // =================================================================
        $display("[TEST] advance=0 freezes priority");
        do_reset_a();
        // First beat: port 0 should win (next starts at 0)
        @(negedge clk); request_a = 5'b11111; advance_a = 0;
        @(posedge clk); #1;
        check("freeze grant[0]", grant_a[0] === 1);
        // Hold advance=0 for 10 more cycles — grant must remain same
        repeat(10) begin
            @(negedge clk); request_a = 5'b11111; advance_a = 0;
            @(posedge clk); #1;
            check("freeze stable", grant_a[0] === 1);
        end
        // Now advance; next grant should be port 1
        @(negedge clk); request_a = 5'b11111; advance_a = 1;
        @(posedge clk); #1;
        advance_a = 0;
        @(negedge clk); request_a = 5'b11111; advance_a = 0;
        @(posedge clk); #1;
        check("after advance grant[1]", grant_a[1] === 1);
        $display("[PASS] advance=0 freezes priority");
        pass_count++;

        // =================================================================
        // TEST 7: Priority wraparound  (port N-1 → back to port 0)
        // =================================================================
        $display("[TEST] Priority wraparound");
        do_reset_a();
        // Cycle through all N ports
        for (i = 0; i < N; i++) begin
            @(negedge clk); request_a = 5'b11111; advance_a = 1;
            @(posedge clk); #1;
            check($sformatf("wraparound step %0d", i), grant_a === (1 << i));
        end
        // After N advances, priority wraps to 0 again
        @(negedge clk); request_a = 5'b11111; advance_a = 0;
        @(posedge clk); #1;
        check("wraparound port 0 again", grant_a[0] === 1);
        $display("[PASS] Priority wraparound");
        pass_count++;

        // =================================================================
        // TEST 8: Dynamic request patterns — port drops out
        // =================================================================
        $display("[TEST] Dynamic request (port dropout)");
        do_reset_a();
        // ports 0,1,2 requesting; after port0 served, it drops out
        @(negedge clk); request_a = 5'b00111; advance_a = 1;
        @(posedge clk); #1;
        check("dynamic step0 port0", grant_a[0] === 1);
        // Port 0 drops; next should be port 1
        @(negedge clk); request_a = 5'b00110; advance_a = 1;
        @(posedge clk); #1;
        check("dynamic step1 port1", grant_a[1] === 1);
        // Port 1 drops; next should be port 2
        @(negedge clk); request_a = 5'b00100; advance_a = 1;
        @(posedge clk); #1;
        check("dynamic step2 port2", grant_a[2] === 1);
        $display("[PASS] Dynamic request (port dropout)");
        pass_count++;

        // =================================================================
        // TEST 9: MINIMIZED=1 gives same results as behavioral for N=5
        // =================================================================
        $display("[TEST] MINIMIZED=1 matches behavioral");
        do_reset_a(); do_reset_b();
        begin
            logic [N-1:0] gnt_b;
            for (i = 0; i < 50; i++) begin
                automatic logic [N-1:0] req = $urandom_range(0, (1<<N)-1);
                // Apply same request and advance to both DUTs simultaneously
                @(negedge clk);
                request_a = req; advance_a = 1;
                request_b = req; advance_b = 1;
                @(posedge clk); #1;
                gnt_b = grant_b;
                advance_a = 0; advance_b = 0;
                check($sformatf("minimized match[%0d]", i), grant_a === gnt_b);
            end
        end
        $display("[PASS] MINIMIZED=1 matches behavioral");
        pass_count++;

        // =================================================================
        // TEST 10: Starvation bound — port 0 served within N advances
        //          even when all ports request continuously
        // =================================================================
        $display("[TEST] Starvation bound");
        do_reset_a();
        begin
            integer wait_count = 0;
            // Advance pointer to some non-zero position first
            for (i = 0; i < 3; i++) begin
                @(negedge clk); request_a=5'b11111; advance_a=1;
                @(posedge clk); #1; advance_a=0;
            end
            // Now track how long until port 0 gets a grant
            wait_count = 0;
            repeat(N+1) begin
                @(negedge clk); request_a=5'b11111; advance_a=1;
                @(posedge clk); #1; advance_a=0;
                if (grant_a[0]) wait_count = 0; else wait_count++;
                check("starvation bound", wait_count < N);
            end
        end
        $display("[PASS] Starvation bound");
        pass_count++;

        // =================================================================
        // RESULTS
        // =================================================================
        if (fail_count == 0)
            $display("[RESULT] tb_rr_arbiter: ALL %0d TESTS PASSED", pass_count);
        else begin
            $display("[RESULT] tb_rr_arbiter: %0d PASSED, %0d FAILED", pass_count, fail_count);
            $fatal(1, "tb_rr_arbiter FAILED");
        end
        $finish;
    end

endmodule
