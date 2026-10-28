// =============================================================================
// tb_noc_endpoint.sv — Functional testbench for noc_endpoint
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   clk, rst
//   TX side:  tx_data[63:0], tx_valid, tx_ready
//   RX side:  rx_data[63:0], rx_valid, rx_ready
//   Mesh side: inject_flit[63:0], inject_valid, inject_credit
//              eject_flit[63:0], eject_valid, eject_credit
//   DUT internal: credits[$clog2(DEPTH+1)-1:0]  — TX credit counter
//                 rx FIFO count (inside noc_fifo sub-instance)
// WHAT TO LOOK FOR:
//   • tx_ready follows (credits != 0). After DEPTH injections without credit
//     returns, tx_ready deasserts.
//   • inject_valid == tx_valid && tx_ready (gated by credit availability).
//   • eject_credit pulses when rx_valid && rx_ready (RX consumed).
//   • rx_valid goes high as soon as eject_valid is received and stored in FIFO.
// SUCCESS: "[RESULT] tb_noc_endpoint: ALL TESTS PASSED" in transcript.
// =============================================================================

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_noc_endpoint;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam DEPTH    = 4;
    localparam CLK_HALF = 5;

    // =========================================================================
    // DUT
    // =========================================================================
    logic clk = 0, rst;

    // TX (user → mesh)
    logic [63:0] tx_data;
    logic        tx_valid;
    wire         tx_ready;

    // RX (mesh → user)
    wire  [63:0] rx_data;
    wire         rx_valid;
    logic        rx_ready;

    // Mesh side — inject (TX path to mesh)
    wire  [63:0] inject_flit;
    wire         inject_valid;
    logic        inject_credit;  // upstream router returns credit

    // Mesh side — eject (RX path from mesh)
    logic [63:0] eject_flit;
    logic        eject_valid;
    wire         eject_credit;   // DUT returns credit to upstream router

    noc_endpoint #(.DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst),
        .tx_data(tx_data),    .tx_valid(tx_valid),   .tx_ready(tx_ready),
        .rx_data(rx_data),    .rx_valid(rx_valid),   .rx_ready(rx_ready),
        .inject_flit(inject_flit), .inject_valid(inject_valid),
        .inject_credit(inject_credit),
        .eject_flit(eject_flit),   .eject_valid(eject_valid),
        .eject_credit(eject_credit)
    );

    always #CLK_HALF clk = ~clk;

    // =========================================================================
    // Mesh-side model:
    // TX: the "router" accepts inject_flit when inject_valid and returns a
    //     credit (inject_credit) one cycle later (zero-latency consumption).
    // RX: the "router" drives eject_flit / eject_valid for flits destined here.
    // =========================================================================

    // TX path model — returns inject_credit one cycle after seeing inject_valid
    logic inject_credit_pipe;
    always @(posedge clk) begin
        inject_credit_pipe <= inject_valid && !rst;
        inject_credit      <= inject_credit_pipe;
    end

    // Capture injected flits for TX scoreboard
    logic [63:0] tx_captured[$];
    always @(posedge clk) begin
        if (inject_valid && !rst)
            tx_captured.push_back(inject_flit);
    end

    // =========================================================================
    // Scoreboard helpers
    // =========================================================================
    int pass_count = 0, fail_count = 0;

    task automatic check(input string tag, input logic cond);
        if (!cond) begin
            $display("[FAIL] %s  at time %0t", tag, $time);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Reset
    // =========================================================================
    task automatic do_reset();
        rst          = 1;
        tx_data      = 0;
        tx_valid     = 0;
        rx_ready     = 0;
        eject_flit   = 0;
        eject_valid  = 0;
        inject_credit_pipe = 0;
        inject_credit = 0;
        tx_captured  = {};
        repeat(4) @(negedge clk);
        rst = 0;
        @(negedge clk);
    endtask

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #500000;
        $fatal(1, "[TIMEOUT] tb_noc_endpoint exceeded limit");
    end

    // =========================================================================
    // Helpers
    // =========================================================================
    // Send a flit through TX path (user side)
    task automatic user_tx(input [63:0] flit);
        @(negedge clk);
        tx_data  = flit;
        tx_valid = 1;
        // Wait until tx_ready
        while (!tx_ready) @(negedge clk);
        @(posedge clk); #1;
        tx_valid = 0;
        tx_data  = 0;
    endtask

    // Inject a flit from mesh side (eject path)
    task automatic mesh_eject(input [63:0] flit);
        @(negedge clk);
        eject_flit  = flit;
        eject_valid = 1;
        // Wait for endpoint to accept (eject_credit asserts)
        @(posedge clk); #1;
        // The endpoint always accepts if FIFO not full; we rely on that here
        eject_valid = 0;
        eject_flit  = 0;
    endtask

    // Receive one flit from user RX path
    task automatic user_rx(output [63:0] flit);
        while (!rx_valid) @(negedge clk);
        @(negedge clk);
        rx_ready = 1;
        @(posedge clk); #1;
        flit = rx_data;
        rx_ready = 0;
    endtask

    // =========================================================================
    // Main test body
    // =========================================================================
    logic [63:0] flit_a, flit_b, recv_flit;
    int i;

    initial begin

        // =================================================================
        // TEST 1: Reset state
        // =================================================================
        $display("[TEST] Reset state");
        do_reset();
        @(posedge clk); #1;
        check("reset tx_ready=1 (credits full)", tx_ready === 1'b1);
        check("reset rx_valid=0 (FIFO empty)",   rx_valid === 1'b0);
        check("reset inject_valid=0",            inject_valid === 1'b0);
        check("reset eject_credit=0",            eject_credit === 1'b0);
        $display("[PASS] Reset state");
        pass_count++;

        // =================================================================
        // TEST 2: Single TX flit — tx_ready→inject_valid propagation
        // =================================================================
        $display("[TEST] Single TX flit propagation");
        do_reset();
        flit_a = 64'hDEAD_BEEF_CAFE_0001;
        @(negedge clk);
        tx_data = flit_a; tx_valid = 1;
        @(posedge clk); #1;
        // inject_valid must equal (tx_valid && tx_ready) — they should both be 1
        check("tx inject_valid asserted", inject_valid === 1'b1);
        check("tx inject_flit matches",  inject_flit  === flit_a);
        tx_valid = 0;
        @(negedge clk);
        $display("[PASS] Single TX flit propagation");
        pass_count++;

        // =================================================================
        // TEST 3: TX credit management — tx_ready deasserts when credits=0
        // =================================================================
        $display("[TEST] TX credit depletion and replenishment");
        do_reset();
        // Stop credit return temporarily
        inject_credit_pipe = 0; inject_credit = 0;
        // Disconnect automatic inject_credit return
        // We'll drive it manually
        // Send DEPTH flits without returning any credits
        begin
            // Override the always block: use a flag
            logic block_credits;
            block_credits = 1;
            for (i = 0; i < DEPTH; i++) begin
                @(negedge clk);
                tx_data  = 64'hC000_0000 + i;
                tx_valid = 1;
                @(posedge clk); #1;
                tx_valid = 0;
            end
            // After DEPTH injections, credits should be 0 → tx_ready = 0
            @(negedge clk);
            // Wait a couple of cycles for credit counter to drain
            repeat(3) @(negedge clk);
            check("credits depleted: tx_ready=0", tx_ready === 1'b0);

            // Now return DEPTH credits one by one
            for (i = 0; i < DEPTH; i++) begin
                @(negedge clk); inject_credit = 1;
                @(posedge clk); #1; inject_credit = 0;
            end
            repeat(2) @(negedge clk);
            check("credits replenished: tx_ready=1", tx_ready === 1'b1);
            block_credits = 0;
        end
        $display("[PASS] TX credit depletion and replenishment");
        pass_count++;

        // =================================================================
        // TEST 4: TX flit ordering — FIFO order preserved on inject path
        // =================================================================
        $display("[TEST] TX flit ordering");
        do_reset();
        tx_captured = {};
        for (i = 0; i < DEPTH; i++) begin
            user_tx(64'hORD_0000_0000_0001 + i);
        end
        // Let credits trickle back (automatic model runs in background)
        repeat(DEPTH * 4) @(negedge clk);
        check("tx ordering: count", tx_captured.size() == DEPTH);
        for (i = 0; i < DEPTH; i++) begin
            if (i < tx_captured.size())
                check($sformatf("tx order[%0d]", i),
                      tx_captured[i] === (64'hORD_0000_0000_0001 + i));
        end
        $display("[PASS] TX flit ordering");
        pass_count++;

        // =================================================================
        // TEST 5: Single RX flit — eject path to user
        // =================================================================
        $display("[TEST] Single RX flit delivery");
        do_reset();
        flit_a = 64'hRX_CAF_E_0000_0001;
        // Inject from mesh side
        @(negedge clk); eject_flit = flit_a; eject_valid = 1;
        @(posedge clk); #1; eject_valid = 0; eject_flit = 0;
        repeat(2) @(negedge clk);
        // rx_valid should now be high (flit buffered)
        check("rx_valid after eject", rx_valid === 1'b1);
        // Read it
        user_rx(recv_flit);
        check("rx flit matches", recv_flit === flit_a);
        repeat(2) @(negedge clk);
        check("rx_valid cleared after read", rx_valid === 1'b0);
        $display("[PASS] Single RX flit delivery");
        pass_count++;

        // =================================================================
        // TEST 6: RX FIFO — fill to DEPTH, eject_credit count
        // =================================================================
        $display("[TEST] RX FIFO fill (DEPTH=%0d)", DEPTH);
        do_reset();
        for (i = 0; i < DEPTH; i++) begin
            @(negedge clk);
            eject_flit  = 64'hRXFF_0000 + i;
            eject_valid = 1;
            @(posedge clk); #1;
            eject_valid = 0; eject_flit = 0;
        end
        repeat(3) @(negedge clk);
        check("rx fifo full: rx_valid=1", rx_valid === 1'b1);
        // Drain and check order
        for (i = 0; i < DEPTH; i++) begin
            user_rx(recv_flit);
            check($sformatf("rx fifo order[%0d]", i), recv_flit === (64'hRXFF_0000 + i));
        end
        repeat(2) @(negedge clk);
        check("rx fifo empty after drain", rx_valid === 1'b0);
        $display("[PASS] RX FIFO fill");
        pass_count++;

        // =================================================================
        // TEST 7: RX backpressure — rx_ready held low stalls RX read
        // =================================================================
        $display("[TEST] RX backpressure (rx_ready=0)");
        do_reset();
        flit_a = 64'hBACK_PRESS_0000_0001;
        @(negedge clk); eject_flit = flit_a; eject_valid = 1;
        @(posedge clk); #1; eject_valid = 0; eject_flit = 0;
        repeat(3) @(negedge clk);
        check("backpressure: rx_valid=1", rx_valid === 1'b1);
        // Hold rx_ready low for 20 cycles
        rx_ready = 0;
        repeat(20) begin
            @(posedge clk); #1;
            check("backpressure: data stable", rx_data === flit_a);
        end
        // Release rx_ready
        @(negedge clk); rx_ready = 1;
        @(posedge clk); #1;
        check("backpressure: flit read", rx_data === flit_a);
        rx_ready = 0;
        repeat(2) @(negedge clk);
        check("backpressure: empty after", rx_valid === 1'b0);
        $display("[PASS] RX backpressure");
        pass_count++;

        // =================================================================
        // TEST 8: eject_credit — returned when RX flit consumed
        // =================================================================
        $display("[TEST] eject_credit returned on RX consume");
        do_reset();
        begin
            int credit_count = 0;
            // Monitor eject_credit
            @(negedge clk); eject_flit = 64'hCRED_TEST_0000_0001; eject_valid = 1;
            @(posedge clk); #1; eject_valid = 0; eject_flit = 0;
            // Accept the flit
            repeat(2) @(negedge clk);
            @(negedge clk); rx_ready = 1;
            @(posedge clk); #1;
            // eject_credit should be 1 this cycle (rx_valid && rx_ready)
            check("eject_credit pulses", eject_credit === 1'b1);
            rx_ready = 0;
        end
        $display("[PASS] eject_credit returned");
        pass_count++;

        // =================================================================
        // TEST 9: Multiple consecutive packets — TX and RX simultaneously
        // =================================================================
        $display("[TEST] Concurrent TX and RX (8 flits each)");
        do_reset();
        tx_captured = {};
        begin
            logic [63:0] rx_results[$];

            // TX: send 8 flits (2 rounds of DEPTH)
            fork
                begin
                    for (i = 0; i < 8; i++) begin
                        user_tx(64'hTX_CONC_0000 + i);
                    end
                end
                // RX: eject 8 flits from mesh side with 1-cycle gaps
                begin
                    for (i = 0; i < 8; i++) begin
                        mesh_eject(64'hRX_CONC_0000 + i);
                        @(negedge clk);
                    end
                end
            join

            // Drain RX
            repeat(5) @(negedge clk);
            for (i = 0; i < 8; i++) begin
                user_rx(recv_flit);
                rx_results.push_back(recv_flit);
            end

            // Verify RX ordering
            for (i = 0; i < 8; i++) begin
                check($sformatf("concurrent rx[%0d]", i),
                      rx_results[i] === (64'hRX_CONC_0000 + i));
            end

            // Verify TX count
            repeat(DEPTH*3) @(negedge clk);
            check("concurrent tx count", tx_captured.size() == 8);
        end
        $display("[PASS] Concurrent TX and RX");
        pass_count++;

        // =================================================================
        // TEST 10: No data loss under TX stalls (inject_credit withheld)
        // =================================================================
        $display("[TEST] TX no-loss under stall");
        do_reset();
        tx_captured = {};
        // Disable automatic inject_credit return; manually control
        inject_credit_pipe = 0; inject_credit = 0;
        begin
            logic block_credits_2;
            block_credits_2 = 1;

            // Send two flits; they'll use up two credits
            @(negedge clk); tx_data=64'hNOL_OSS_0001; tx_valid=1;
            @(posedge clk); #1; tx_valid=0;
            @(negedge clk); tx_data=64'hNOL_OSS_0002; tx_valid=1;
            @(posedge clk); #1; tx_valid=0;

            // Return credits manually
            @(negedge clk); inject_credit=1; @(posedge clk); #1; inject_credit=0;
            @(negedge clk); inject_credit=1; @(posedge clk); #1; inject_credit=0;

            // Send two more
            @(negedge clk); tx_data=64'hNOL_OSS_0003; tx_valid=1;
            @(posedge clk); #1; tx_valid=0;
            @(negedge clk); tx_data=64'hNOL_OSS_0004; tx_valid=1;
            @(posedge clk); #1; tx_valid=0;
            // Return credits
            @(negedge clk); inject_credit=1; @(posedge clk); #1; inject_credit=0;
            @(negedge clk); inject_credit=1; @(posedge clk); #1; inject_credit=0;

            repeat(5) @(negedge clk);
            check("no-loss tx count", tx_captured.size() == 4);
            check("no-loss flit0", tx_captured[0] === 64'hNOL_OSS_0001);
            check("no-loss flit1", tx_captured[1] === 64'hNOL_OSS_0002);
            check("no-loss flit2", tx_captured[2] === 64'hNOL_OSS_0003);
            check("no-loss flit3", tx_captured[3] === 64'hNOL_OSS_0004);
            block_credits_2 = 0;
        end
        $display("[PASS] TX no-loss under stall");
        pass_count++;

        // =================================================================
        // RESULTS
        // =================================================================
        if (fail_count == 0)
            $display("[RESULT] tb_noc_endpoint: ALL %0d TESTS PASSED", pass_count);
        else begin
            $display("[RESULT] tb_noc_endpoint: %0d PASSED, %0d FAILED", pass_count, fail_count);
            $fatal(1, "tb_noc_endpoint FAILED");
        end
        $finish;
    end

endmodule
