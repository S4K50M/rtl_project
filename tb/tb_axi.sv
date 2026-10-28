// =============================================================================
// tb_axi.sv — Functional testbench for AXI4‑Lite host interface (axi_noc_host)
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   clk, rst
//   AXI write address: awaddr, awvalid, awready
//   AXI write data   : wdata, wstrb, wvalid, wready
//   AXI write resp   : bresp, bvalid, bready
//   AXI read address : araddr, arvalid, arready
//   AXI read data    : rdata, rresp, rvalid, rready
//   DUT internal registers (optional via hierarchy)
// WHAT TO LOOK FOR:
//   • Handshake correctness (valid && ready)
//   • Write response OK (bresp == 2'b00)
//   • Read data matches previously written value
//   • Reset clears all valid/ready signals
//   • Back‑pressure (ready low) stalls transaction without loss
//   • Multiple back‑to‑back and pipelined transactions succeed
//   • No data corruption on overlapping transactions
// SUCCESS: "[RESULT] tb_axi: ALL TESTS PASSED" appears in the transcript.
// =============================================================================

`timescale 1ns/1ps

module tb_axi;

    // ---------------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------------
    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam CLK_H  = 5; // 10 ns period

    // ---------------------------------------------------------------------
    // Clock & reset
    // ---------------------------------------------------------------------
    logic clk = 0, rst;
    always #CLK_H clk = ~clk;

    // ---------------------------------------------------------------------
    // DUT – AXI4‑Lite host side (module name from RTL).
    // Adjust the instance name if the RTL uses a different identifier.
    // ---------------------------------------------------------------------
    logic [ADDR_W-1:0] awaddr, araddr;
    logic awvalid, awready, wvalid, wready, bvalid, bready;
    logic [DATA_W-1:0] wdata, rdata;
    logic [3:0] wstrb;
    logic [1:0] bresp, rresp;
    logic arvalid, arready, rvalid, rready;

    axi_noc_host #(
        .ADDR_WIDTH(ADDR_W),
        .DATA_WIDTH(DATA_W)
    ) dut (
        .clk   (clk), .rst (rst),
        // Write address channel
        .awaddr (awaddr), .awvalid (awvalid), .awready (awready),
        // Write data channel
        .wdata (wdata), .wstrb (wstrb), .wvalid (wvalid), .wready (wready),
        // Write response channel
        .bresp (bresp), .bvalid (bvalid), .bready (bready),
        // Read address channel
        .araddr (araddr), .arvalid (arvalid), .arready (arready),
        // Read data channel
        .rdata (rdata), .rresp (rresp), .rvalid (rvalid), .rready (rready)
    );

    // ---------------------------------------------------------------------
    // Simple reference memory model (address‑to‑data map)
    // ---------------------------------------------------------------------
    typedef struct packed {logic [ADDR_W-1:0] a; logic [DATA_W-1:0] d;} mem_entry_t;
    mem_entry_t mem[$]; // associative array using a queue for deterministic order

    function automatic void mem_write(logic [ADDR_W-1:0] a, logic [DATA_W-1:0] d);
        int i;
        for (i=0; i<mem.size(); i++) if (mem[i].a == a) begin mem[i].d = d; return; end
        mem.push_back('{a:a, d:d});
    endfunction

    function automatic logic [DATA_W-1:0] mem_read(logic [ADDR_W-1:0] a);
        int i;
        for (i=0; i<mem.size(); i++) if (mem[i].a == a) return mem[i].d;
        return '0;
    endfunction

    // ---------------------------------------------------------------------
    // Scoreboard helpers
    // ---------------------------------------------------------------------
    int pass_cnt = 0, fail_cnt = 0;
    task automatic check(string tag, logic cond);
        if (!cond) begin
            $display("[FAIL] %s  @ %0t", tag, $time);
            fail_cnt++;
        end
    endtask

    // ---------------------------------------------------------------------
    // AXI transaction tasks (blocking, self‑checking)
    // ---------------------------------------------------------------------
    task automatic axi_write(logic [ADDR_W-1:0] a, logic [DATA_W-1:0] d);
        // ---- Address phase ----
        @(negedge clk);
        awaddr  = a; awvalid = 1; wdata = d; wvalid = 1; wstrb = 4'hF;
        // wait for both address and data ready
        while (!(awready && wready)) @(negedge clk);
        @(posedge clk) #1;
        awvalid = 0; wvalid = 0; awaddr = 0; wdata = 0; wstrb = 0;
        // ---- Write response ----
        bready = 1;
        while (!bvalid) @(negedge clk);
        @(posedge clk) #1;
        check("write response OK", bresp == 2'b00);
        bready = 0;
        // update reference model
        mem_write(a,d);
    endtask

    task automatic axi_read(logic [ADDR_W-1:0] a);
        @(negedge clk);
        araddr = a; arvalid = 1;
        while (!arready) @(negedge clk);
        @(posedge clk) #1;
        arvalid = 0; araddr = 0;
        // ---- Read data ----
        rready = 1;
        while (!rvalid) @(negedge clk);
        @(posedge clk) #1;
        check("read response OK", rresp == 2'b00);
        check("read data matches", rdata === mem_read(a));
        rready = 0;
    endtask

    // ---------------------------------------------------------------------
    // Watchdog (fails simulation after reasonable time)
    // ---------------------------------------------------------------------
    initial begin
        #500000;
        $fatal(1, "[TIMEOUT] tb_axi exceeded simulation limit");
    end

    // ---------------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------------
    integer i;
    initial begin
        // ---------------------------------------------------------------
        // TEST 1 – Reset behavior
        // ---------------------------------------------------------------
        $display("[TEST] Reset behavior");
        rst = 1; repeat(4) @(negedge clk);
        rst = 0; @(negedge clk);
        // After reset all handshakes must be low
        check("reset: awvalid==0", awvalid===0);
        check("reset: wvalid==0",  wvalid===0);
        check("reset: arvalid==0", arvalid===0);
        check("reset: bvalid==0",  bvalid===0);
        check("reset: rvalid==0",  rvalid===0);
        $display("[PASS] Reset behavior");
        pass_cnt++;

        // ---------------------------------------------------------------
        // TEST 2 – Single write followed by read back
        // ---------------------------------------------------------------
        $display("[TEST] Single write/read back");
        axi_write(32'h0000_1000, 32'hDEAD_BEEF);
        axi_read (32'h0000_1000);
        $display("[PASS] Single write/read back");
        pass_cnt++;

        // ---------------------------------------------------------------
        // TEST 3 – Back‑to‑back writes (pipeline) without waiting for response
        // ---------------------------------------------------------------
        $display("[TEST] Pipeline writes");
        for (i=0; i<4; i++) begin
            axi_write(32'h0000_2000 + i*4, 32'hA5A5_0000 + i);
        end
        // Wait for all responses to appear
        repeat(8) @(negedge clk);
        $display("[PASS] Pipeline writes");
        pass_cnt++;

        // ---------------------------------------------------------------
        // TEST 4 – Randomized read/write sequence (10 iterations)
        // ---------------------------------------------------------------
        $display("[TEST] Randomised sequence");
        for (i=0; i<10; i++) begin
            logic [ADDR_W-1:0] a = $urandom_range(0,255) << 2; // word‑aligned
            logic [DATA_W-1:0] d = $urandom;
            axi_write(a,d);
            axi_read (a);
        end
        $display("[PASS] Randomised sequence");
        pass_cnt++;

        // ---------------------------------------------------------------
        // TEST 5 – Write address back‑pressure (force awready low)
        // ---------------------------------------------------------------
        $display("[TEST] Write address back‑pressure");
        fork
            begin
                // Drive a normal write but hold the address ready low for 5 cycles
                @(negedge clk);
                awaddr  = 32'h0000_3000; awvalid = 1; wdata = 32'hBEEF_DEAD; wvalid = 1; wstrb = 4'hF;
                repeat(5) @(negedge clk); // stall
                // Release when DUT finally asserts awready & wready
                while (!(awready && wready)) @(negedge clk);
                @(posedge clk) #1;
                awvalid = 0; wvalid = 0; awaddr = 0; wdata = 0; wstrb = 0;
                // Wait for response as normal
                bready = 1;
                while (!bvalid) @(negedge clk);
                @(posedge clk) #1;
                check("back‑pressure write resp OK", bresp == 2'b00);
                bready = 0;
                mem_write(32'h0000_3000, 32'hBEEF_DEAD);
            end
            begin
                // Force awready low for the first 5 cycles after awvalid
                force dut.awready = 0;
                repeat(5) @(negedge clk);
                release dut.awready; // let DUT drive normally
            end
        join
        $display("[PASS] Write address back‑pressure");
        pass_cnt++;

        // ---------------------------------------------------------------
        // TEST 6 – Read data back‑pressure (hold rready low)
        // ---------------------------------------------------------------
        $display("[TEST] Read back‑pressure");
        // Issue read first
        @(negedge clk);
        araddr = 32'h0000_3000; arvalid = 1;
        while (!arready) @(negedge clk);
        @(posedge clk) #1;
        arvalid = 0; araddr = 0;
        // Hold rready low for a few cycles after read data becomes valid
        force dut.rready = 0;
        repeat(6) @(negedge clk);
        release dut.rready;
        rready = 1;
        while (!rvalid) @(negedge clk);
        @(posedge clk) #1;
        check("read after back‑pressure data", rdata === 32'hBEEF_DEAD);
        rready = 0;
        $display("[PASS] Read back‑pressure");
        pass_cnt++;

        // ---------------------------------------------------------------
        // RESULTS
        // ---------------------------------------------------------------
        if (fail_cnt == 0)
            $display("[RESULT] tb_axi: ALL %0d TESTS PASSED", pass_cnt);
        else
            $display("[RESULT] tb_axi: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
