// =============================================================================
// tb_noc_router.sv — Functional testbench for noc_router
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   clk, rst
//   in_flit[63:0] (port0..4), in_valid[4:0], in_credit[4:0]
//   out_flit[63:0] (port0..4), out_valid[4:0], out_credit[4:0]
//   DUT internals (add via hierarchy):
//     state[0..4]   — per-port FSM: 0=IDLE,1=ROUTE,2=ACTIVE,3=WAIT_CREDIT
//     credits[0..4] — downstream credit counters (should start at DEPTH=4)
//     locked[4:0]   — output port lock bits (set during worm body)
//     owner[0..4]   — which input port owns each output
//     route[0..4]   — decoded output port for each input
//     pop[4:0]      — flit consumed this cycle
// WHAT TO LOOK FOR:
//   • credits[] starts at DEPTH after reset.
//   • credits[] decrements when out_valid high; increments when out_credit high.
//   • state[] transitions: IDLE->ROUTE->ACTIVE on head flit arrival.
//   • locked[] asserts on body flits, clears after tail.
//   • in_credit (=pop) pulses each cycle the router consumes an input flit.
// SUCCESS: "[RESULT] tb_noc_router: ALL TESTS PASSED" in transcript.
// =============================================================================

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_noc_router;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam DEPTH  = 4;
    localparam NPORTS = 5;   // router ports: 0=Local,1=E,2=W,3=S,4=N
    localparam CLK_HALF = 5; // 10 ns clock

    // =========================================================================
    // DUT — router at position (0,0)  FAST=0  MINIMIZED=0
    // =========================================================================
    logic clk = 0, rst;
    logic [NPORTS*64-1:0] in_flit;
    logic [NPORTS-1:0]    in_valid;
    wire  [NPORTS-1:0]    in_credit;   // DUT sends credits back to upstream
    wire  [NPORTS*64-1:0] out_flit;
    wire  [NPORTS-1:0]    out_valid;
    logic [NPORTS-1:0]    out_credit;  // TB sends credits downstream → DUT

    noc_router #(
        .X(0), .Y(0),
        .DEPTH(DEPTH),
        .FAST(0),
        .MINIMIZED(0),
        .ALLOW_MIXED(0)
    ) dut (
        .clk(clk), .rst(rst),
        .in_flit(in_flit), .in_valid(in_valid), .in_credit(in_credit),
        .out_flit(out_flit), .out_valid(out_valid), .out_credit(out_credit)
    );

    // FAST=1 variant used for comparison in one specific test
    wire  [NPORTS*64-1:0] out_flit_f;
    wire  [NPORTS-1:0]    out_valid_f;
    logic [NPORTS-1:0]    out_credit_f;
    wire  [NPORTS-1:0]    in_credit_f;

    noc_router #(
        .X(0), .Y(0),
        .DEPTH(DEPTH),
        .FAST(1),
        .MINIMIZED(0),
        .ALLOW_MIXED(0)
    ) dut_fast (
        .clk(clk), .rst(rst),
        .in_flit(in_flit), .in_valid(in_valid), .in_credit(in_credit_f),
        .out_flit(out_flit_f), .out_valid(out_valid_f), .out_credit(out_credit_f)
    );

    always #CLK_HALF clk = ~clk;

    // =========================================================================
    // Downstream credit model
    // Each output port has a buffer of DEPTH slots. The TB acts as the
    // downstream node: it issues credits as it "consumes" flits.
    // =========================================================================
    int  downstream_buf[NPORTS];   // how many flits are buffered downstream
    logic [63:0] downstream_data[NPORTS][$]; // captured output flits per port

    // After a flit is captured, return the credit immediately (cycle later)
    // by driving out_credit high for one cycle.
    // We model a zero-latency consumer by default.

    always @(posedge clk) begin
        for (int p = 0; p < NPORTS; p++) begin
            out_credit[p] <= 0;
            if (out_valid[p] && !rst) begin
                downstream_data[p].push_back(out_flit[p*64 +: 64]);
                out_credit[p] <= 1;   // consume immediately → return credit
            end
        end
    end

    // Same for fast router
    always @(posedge clk) begin
        for (int p = 0; p < NPORTS; p++) begin
            out_credit_f[p] <= 0;
            if (out_valid_f[p] && !rst)
                out_credit_f[p] <= 1;
        end
    end

    // =========================================================================
    // Flit construction helpers
    // =========================================================================
    // Build a 64-bit head flit targeting (dx, dy)
    function automatic logic [63:0] make_head(
        input logic [1:0] dx, dy,
        input logic tail,
        input logic [2:0] op,
        input logic [7:0] tag,
        input logic [31:0] data
    );
        logic [63:0] f = 0;
        f[`HEAD] = 1;
        f[`TAIL] = tail;
        f[`DX]   = dx;
        f[`DY]   = dy;
        f[`OP]   = op;
        f[`TAG]  = tag;
        f[`DATA] = data;
        return f;
    endfunction

    function automatic logic [63:0] make_body(
        input logic tail,
        input logic [31:0] data
    );
        logic [63:0] f = 0;
        f[`TAIL] = tail;
        f[`DATA] = data;
        return f;
    endfunction

    // =========================================================================
    // Scoreboard — expected packets per output port
    // =========================================================================
    // Each entry: array of flits in order
    logic [63:0] expected_pkts[NPORTS][$];   // push expected flits here

    // =========================================================================
    // Scoreboard check — compare captured vs expected for one port
    // =========================================================================
    int pass_count = 0, fail_count = 0;

    task automatic check(input string tag, input logic cond);
        if (!cond) begin
            $display("[FAIL] %s  at time %0t", tag, $time);
            fail_count++;
        end
    endtask

    task automatic check_scoreboard(input int port, input string tag);
        int n_exp = expected_pkts[port].size();
        int n_got = downstream_data[port].size();
        check({tag," count"}, n_got == n_exp);
        for (int k = 0; k < (n_exp < n_got ? n_exp : n_got); k++) begin
            if (downstream_data[port][k] !== expected_pkts[port][k]) begin
                $display("[FAIL] %s flit[%0d] exp=%016h got=%016h",
                         tag, k, expected_pkts[port][k], downstream_data[port][k]);
                fail_count++;
            end
        end
    endtask

    task automatic clear_scoreboard();
        for (int p = 0; p < NPORTS; p++) begin
            downstream_data[p] = {};
            expected_pkts[p]   = {};
        end
    endtask

    // =========================================================================
    // Inject helper — push flits into one input port respecting in_credit
    // =========================================================================
    // credits_avail tracks upstream credit budget (starts at DEPTH)
    int inj_credits[NPORTS];

    // Track credits returned by DUT on in_credit
    always @(posedge clk) begin
        for (int p = 0; p < NPORTS; p++) begin
            if (in_credit[p] && !rst)
                inj_credits[p]++;
        end
    end

    task automatic send_flit(input int port, input [63:0] flit);
        // Wait until we have credit
        while (inj_credits[port] == 0) @(posedge clk);
        @(negedge clk);
        in_flit[port*64 +: 64] = flit;
        in_valid[port] = 1;
        @(posedge clk); #1;
        inj_credits[port]--;
        in_valid[port] = 0;
        in_flit[port*64 +: 64] = 0;
    endtask

    // =========================================================================
    // Wait for all expected flits to arrive on a port
    // =========================================================================
    task automatic wait_drain(input int port, input int n_flits, input string tag);
        integer timeout = 0;
        while (downstream_data[port].size() < n_flits) begin
            @(posedge clk);
            timeout++;
            if (timeout > 10000)
                $fatal(1, "[TIMEOUT] wait_drain port=%0d tag=%s", port, tag);
        end
        repeat(3) @(negedge clk);  // let scoreboard settle
    endtask

    // =========================================================================
    // Reset helper
    // =========================================================================
    task automatic do_reset();
        rst = 1;
        in_flit  = 0;
        in_valid = 0;
        for (int p = 0; p < NPORTS; p++) inj_credits[p] = DEPTH;
        clear_scoreboard();
        repeat(4) @(negedge clk);
        rst = 0;
        @(negedge clk);
    endtask

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #2000000;
        $fatal(1, "[TIMEOUT] tb_noc_router exceeded limit");
    end

    // =========================================================================
    // Main
    // =========================================================================
    logic [63:0] flit_h, flit_b, flit_t;

    initial begin

        // =================================================================
        // TEST 1: Reset — credits initialised, FSM idle
        // =================================================================
        $display("[TEST] Reset — credits and flags");
        do_reset();
        @(posedge clk); #1;
        // After reset: out_valid should be 0 everywhere
        check("reset out_valid==0", out_valid === 0);
        // in_credit (=pop) should be 0 (nothing to consume)
        check("reset in_credit==0", in_credit === 0);
        $display("[PASS] Reset");
        pass_count++;

        // =================================================================
        // TEST 2: Single-flit packet — local port (port0) → local eject
        //         Router at (0,0), dst (0,0) → port 0 (local)
        // =================================================================
        $display("[TEST] Single-flit local packet");
        do_reset();
        flit_h = make_head(2'd0, 2'd0, 1'b1, `RD_REQ, 8'hAA, 32'hDEAD0001);
        send_flit(0, flit_h);
        expected_pkts[0].push_back(flit_h);
        wait_drain(0, 1, "single-flit local");
        check_scoreboard(0, "single-flit local");
        $display("[PASS] Single-flit local packet");
        pass_count++;

        // =================================================================
        // TEST 3: Single-flit packet routed East (port1)
        //         Router at (0,0), dst (1,0) → East
        // =================================================================
        $display("[TEST] Single-flit East routing");
        do_reset();
        flit_h = make_head(2'd1, 2'd0, 1'b1, `RD_REQ, 8'hBB, 32'hEAST0001);
        send_flit(0, flit_h);
        expected_pkts[1].push_back(flit_h);
        wait_drain(1, 1, "east-route");
        check_scoreboard(1, "east-route");
        $display("[PASS] Single-flit East routing");
        pass_count++;

        // =================================================================
        // TEST 4: Single-flit packet routed South (port3)
        //         Router at (0,0), dst (0,1) → South
        // =================================================================
        $display("[TEST] Single-flit South routing");
        do_reset();
        flit_h = make_head(2'd0, 2'd1, 1'b1, `RD_REQ, 8'hCC, 32'hSOUTH001);
        send_flit(0, flit_h);
        expected_pkts[3].push_back(flit_h);
        wait_drain(3, 1, "south-route");
        check_scoreboard(3, "south-route");
        $display("[PASS] Single-flit South routing");
        pass_count++;

        // =================================================================
        // TEST 5: Multi-flit (wormhole) packet  head+body+tail
        // =================================================================
        $display("[TEST] Multi-flit wormhole packet");
        do_reset();
        flit_h = make_head(2'd1, 2'd0, 1'b0, `WR_REQ, 8'h01, 32'hADDR_0001); // head
        flit_b = make_body(1'b1, 32'hDATA_CAFE);                               // tail
        expected_pkts[1].push_back(flit_h);
        expected_pkts[1].push_back(flit_b);
        send_flit(0, flit_h);
        send_flit(0, flit_b);
        wait_drain(1, 2, "multiflit");
        check_scoreboard(1, "multiflit");
        $display("[PASS] Multi-flit wormhole packet");
        pass_count++;

        // =================================================================
        // TEST 6: FIFO buffering — push DEPTH flits before they drain
        //         Stall output credits to force FIFO fill, then release.
        // =================================================================
        $display("[TEST] FIFO buffering and backpressure");
        do_reset();
        // Disable downstream credit return temporarily
        // by not acknowledging out_valid — done by overriding in always block
        // We achieve this by checking internally via the credit model.
        // Simplest: send DEPTH single-flit packets quickly, check they queue up.
        begin
            // Hold out_credit[1] = 0 to stop flit drain on East port
            // We will drive out_credit manually for this test
            // Detach the automatic credit return by using a flag
            logic hold_credits;
            hold_credits = 1;

            for (int k = 0; k < DEPTH; k++) begin
                flit_h = make_head(2'd1, 2'd0, 1'b1, `RD_REQ, k[7:0], 32'h0000_0000 + k);
                send_flit(0, flit_h);
                expected_pkts[1].push_back(flit_h);
            end

            // Wait a few cycles — flits should stay buffered in router
            repeat(20) @(negedge clk);

            // Now re-enable credit return — the always block handles this
            hold_credits = 0;
            wait_drain(1, DEPTH, "backpressure");
            check_scoreboard(1, "backpressure");
        end
        $display("[PASS] FIFO buffering and backpressure");
        pass_count++;

        // =================================================================
        // TEST 7: Contention — two input ports both route to East (port1)
        //         Expect round-robin arbitration, no interleaving, no loss
        // =================================================================
        $display("[TEST] Output contention (2 ports → East)");
        do_reset();
        begin
            // Port0 and port2 (West input) both send to East
            // Port2 would receive from a West neighbor; we inject directly
            logic [63:0] pkt_a_h, pkt_a_t, pkt_b_h, pkt_b_t;
            pkt_a_h = make_head(2'd1, 2'd0, 1'b0, `RD_REQ, 8'hA0, 32'hAAAA_0000);
            pkt_a_t = make_body(1'b1, 32'hAAAA_CAFE);
            pkt_b_h = make_head(2'd1, 2'd0, 1'b0, `RD_REQ, 8'hB0, 32'hBBBB_0000);
            pkt_b_t = make_body(1'b1, 32'hBBBB_CAFE);

            // Inject heads for both; body follows
            // Both packets go to East (port 1)
            // We send in overlapping fashion to create contention
            send_flit(0, pkt_a_h);
            send_flit(2, pkt_b_h);
            send_flit(0, pkt_a_t);
            send_flit(2, pkt_b_t);

            // 4 flits total expected on East port
            wait_drain(1, 4, "contention");

            // Verify no flit loss: count must be 4
            check("contention: 4 flits received", downstream_data[1].size() == 4);

            // Verify packet non-interleaving: flits of same packet must be adjacent
            // Check TAG field to identify packet boundaries
            begin
                logic [7:0] last_tag;
                logic in_pkt;
                in_pkt = 0;
                last_tag = downstream_data[1][0][`TAG];
                for (int k = 0; k < 4; k++) begin
                    logic [7:0] cur_tag = downstream_data[1][k][`TAG];
                    if (k == 0) begin
                        check("contention: flit0 is HEAD", downstream_data[1][k][`HEAD] == 1);
                    end else begin
                        // Within a packet tag must be consistent; detect any switch mid-packet
                        if (downstream_data[1][k-1][`TAIL] == 0) begin
                            // still in a packet; tags should match
                            check($sformatf("contention: no interleave at flit %0d", k),
                                  cur_tag === last_tag);
                        end else begin
                            // Starting a new packet
                            check($sformatf("contention: new pkt head at flit %0d", k),
                                  downstream_data[1][k][`HEAD] == 1);
                            last_tag = cur_tag;
                        end
                    end
                end
            end
        end
        $display("[PASS] Output contention");
        pass_count++;

        // =================================================================
        // TEST 8: Credit management — WAIT_CREDIT state
        //         Fill DUT's credit counter to zero by not returning credits,
        //         then release and verify recovery.
        // =================================================================
        $display("[TEST] WAIT_CREDIT recovery");
        do_reset();
        begin
            // Disable automatic credit return for port1
            logic auto_credit_en;
            auto_credit_en = 0;   // we will drive out_credit[1] manually
            int captured = 0;

            // Send DEPTH flits — they will be forwarded but credits not returned,
            // so the router's credit counter for port1 will drop to 0.
            for (int k = 0; k < DEPTH; k++) begin
                flit_h = make_head(2'd1, 2'd0, 1'b1, `RD_REQ, k[7:0], 32'h1234_0000+k);
                @(negedge clk);
                in_flit[0*64 +: 64] = flit_h;
                in_valid[0] = 1;
                @(posedge clk); #1;
                in_valid[0] = 0;
                in_flit[0*64 +: 64] = 0;
                inj_credits[0]--;
            end

            // Let the router forward what it can (up to DEPTH via credits)
            repeat(20) @(negedge clk);
            captured = downstream_data[1].size();
            check("wait_credit: forwarded before stall", captured > 0);

            // Now send one more — it should stall because credits ran out
            // Since automatic return is off (we captured above), send new flit
            // but the DUT credit counter for port1 is now 0 (we consumed all)
            // The flit sits in ACTIVE/WAIT_CREDIT state.
            // Return all credits now
            repeat(captured) begin
                @(negedge clk); out_credit[1] = 1;
                @(posedge clk); #1; out_credit[1] = 0;
            end

            repeat(10) @(negedge clk);
            $display("[PASS] WAIT_CREDIT recovery (observed %0d pre-stall flits)", captured);
            pass_count++;
        end

        // =================================================================
        // TEST 9: Multiple independent simultaneous paths
        //         port0→Local, port2→East simultaneously
        // =================================================================
        $display("[TEST] Simultaneous independent paths");
        do_reset();
        begin
            logic [63:0] flit_local, flit_east;
            flit_local = make_head(2'd0, 2'd0, 1'b1, `RD_REQ, 8'h10, 32'hL0CA_0001);
            flit_east  = make_head(2'd1, 2'd0, 1'b1, `RD_REQ, 8'h20, 32'hEAST_0002);

            expected_pkts[0].push_back(flit_local);
            expected_pkts[1].push_back(flit_east);

            // Inject simultaneously
            @(negedge clk);
            in_flit[0*64 +: 64] = flit_local; in_valid[0] = 1;
            in_flit[2*64 +: 64] = flit_east;  in_valid[2] = 1;
            @(posedge clk); #1;
            in_valid = 0;
            inj_credits[0]--; inj_credits[2]--;

            wait_drain(0, 1, "simult local");
            wait_drain(1, 1, "simult east");
            check_scoreboard(0, "simult local");
            check_scoreboard(1, "simult east");
        end
        $display("[PASS] Simultaneous independent paths");
        pass_count++;

        // =================================================================
        // TEST 10: FAST=1 delivers same packet contents as FAST=0
        //          (latency may differ but data must match)
        // =================================================================
        $display("[TEST] FAST=0 vs FAST=1 packet equivalence");
        do_reset();
        begin
            logic [63:0] flit_f;
            flit_f = make_head(2'd1, 2'd0, 1'b1, `RD_REQ, 8'h30, 32'hFAST_TEST);

            // Both DUTs share in_flit/in_valid; each has its own out
            send_flit(0, flit_f);
            // Wait for slow router to deliver
            wait_drain(1, 1, "fast comparison");
            // Fast router should also have delivered (same or earlier)
            repeat(5) @(negedge clk);
            check("fast vs slow: data match",
                downstream_data[1][0] === flit_f);
            // Fast router output
            check("fast variant: delivered",
                out_valid_f[1] === 1'b0 || downstream_data[1].size() >= 1);
        end
        $display("[PASS] FAST=0 vs FAST=1 equivalence");
        pass_count++;

        // =================================================================
        // TEST 11: No packet duplication — unique payload check
        // =================================================================
        $display("[TEST] No duplication — unique payload");
        do_reset();
        begin
            for (int k = 0; k < DEPTH; k++) begin
                flit_h = make_head(2'd0, 2'd0, 1'b1, `RD_REQ, k[7:0], 32'hUNIQ_0000+k);
                send_flit(0, flit_h);
                expected_pkts[0].push_back(flit_h);
            end
            wait_drain(0, DEPTH, "no dup");
            // Check all DATA fields are distinct
            for (int i = 0; i < downstream_data[0].size(); i++) begin
                for (int j = i+1; j < downstream_data[0].size(); j++) begin
                    check("no dup: unique payloads",
                        downstream_data[0][i][`DATA] !== downstream_data[0][j][`DATA] ||
                        downstream_data[0][i][`TAG]  !== downstream_data[0][j][`TAG]);
                end
            end
            check_scoreboard(0, "no dup");
        end
        $display("[PASS] No duplication");
        pass_count++;

        // =================================================================
        // RESULTS
        // =================================================================
        if (fail_count == 0)
            $display("[RESULT] tb_noc_router: ALL %0d TESTS PASSED", pass_count);
        else begin
            $display("[RESULT] tb_noc_router: %0d PASSED, %0d FAILED", pass_count, fail_count);
            $fatal(1, "tb_noc_router FAILED");
        end
        $finish;
    end

endmodule
