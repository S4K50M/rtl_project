// =============================================================================
// tb_xy_route.sv — Functional testbench for xy_route
// =============================================================================
// WAVEFORM GUIDE (add to Vivado waveform window):
//   dx[1:0], dy[1:0], port[2:0]   (for each DUT instance)
// WHAT TO LOOK FOR:
//   • When dx > X: port = 1 (East)
//   • When dx < X: port = 2 (West)
//   • When dx == X and dy > Y: port = 3 (South)
//   • When dx == X and dy < Y: port = 4 (North)
//   • When dx == X and dy == Y: port = 0 (Local)
//   • Minimized and behavioral outputs must always match.
// PORT ENCODING: 0=Local, 1=East, 2=West, 3=South, 4=North
// SUCCESS: "[RESULT] tb_xy_route: ALL TESTS PASSED" in transcript.
// =============================================================================

`timescale 1ns/1ps

module tb_xy_route;

    // -------------------------------------------------------------------------
    // xy_route is purely combinational — no clock needed for the DUT.
    // We use a clock only to sequence tests in a readable waveform.
    // -------------------------------------------------------------------------
    logic clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Reference function — canonical XY routing decision
    // Parameters: router located at (RX, RY); packet destined for (dx, dy)
    // -------------------------------------------------------------------------
    function automatic logic [2:0] xy_ref(
        input logic [1:0] dx, dy,
        input integer RX, RY
    );
        if      (dx > RX) return 3'd1;   // East
        else if (dx < RX) return 3'd2;   // West
        else if (dy > RY) return 3'd3;   // South
        else if (dy < RY) return 3'd4;   // North
        else              return 3'd0;   // Local
    endfunction

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_count = 0, fail_count = 0;
    int check_count = 0;

    task automatic check_port(
        input string  tag,
        input [2:0]   actual,
        input [2:0]   expected,
        input [1:0]   dx_v, dy_v,
        input integer rx_v, ry_v
    );
        check_count++;
        if (actual !== expected) begin
            $display("[FAIL] %s  dx=%0d dy=%0d @(%0d,%0d)  expected=%0d got=%0d  t=%0t",
                     tag, dx_v, dy_v, rx_v, ry_v, expected, actual, $time);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Exhaustive 2×2 grid sweep helper
    // -------------------------------------------------------------------------
    task automatic sweep_2x2(
        input integer RX, RY,
        input logic   minimized
    );
        logic [1:0] dx, dy;
        logic [2:0] expected_port, actual_port;

        // DUT ports are driven by continuous-assignment logic inside the
        // generate block; we parameterize by re-instantiating two DUTs below.
        // This task is called with the correct DUT outputs passed in.
    endtask

    // =========================================================================
    // Instantiate DUTs for every (X,Y) in a 3×3 grid
    // =========================================================================
    // We use a flat set of instances.  xy_route is combinational so we just
    // drive dx/dy and read port immediately (no clock dependency).

    logic [1:0] dx_s, dy_s;  // shared stimulus

    // 2×2 grid — behavioral
    wire [2:0] p_b00, p_b10, p_b01, p_b11;
    xy_route #(.X(0),.Y(0),.MINIMIZED(0)) dut_b00(.dx(dx_s),.dy(dy_s),.port(p_b00));
    xy_route #(.X(1),.Y(0),.MINIMIZED(0)) dut_b10(.dx(dx_s),.dy(dy_s),.port(p_b10));
    xy_route #(.X(0),.Y(1),.MINIMIZED(0)) dut_b01(.dx(dx_s),.dy(dy_s),.port(p_b01));
    xy_route #(.X(1),.Y(1),.MINIMIZED(0)) dut_b11(.dx(dx_s),.dy(dy_s),.port(p_b11));

    // 2×2 grid — minimized
    wire [2:0] p_m00, p_m10, p_m01, p_m11;
    xy_route #(.X(0),.Y(0),.MINIMIZED(1)) dut_m00(.dx(dx_s),.dy(dy_s),.port(p_m00));
    xy_route #(.X(1),.Y(0),.MINIMIZED(1)) dut_m10(.dx(dx_s),.dy(dy_s),.port(p_m10));
    xy_route #(.X(0),.Y(1),.MINIMIZED(1)) dut_m01(.dx(dx_s),.dy(dy_s),.port(p_m01));
    xy_route #(.X(1),.Y(1),.MINIMIZED(1)) dut_m11(.dx(dx_s),.dy(dy_s),.port(p_m11));

    // Extra 3×3 routers — behavioral (X,Y up to 2)
    wire [2:0] p_b22, p_b12, p_b21, p_b20, p_b02;
    xy_route #(.X(2),.Y(2),.MINIMIZED(0)) dut_b22(.dx(dx_s),.dy(dy_s),.port(p_b22));
    xy_route #(.X(1),.Y(2),.MINIMIZED(0)) dut_b12(.dx(dx_s),.dy(dy_s),.port(p_b12));
    xy_route #(.X(2),.Y(1),.MINIMIZED(0)) dut_b21(.dx(dx_s),.dy(dy_s),.port(p_b21));
    xy_route #(.X(2),.Y(0),.MINIMIZED(0)) dut_b20(.dx(dx_s),.dy(dy_s),.port(p_b20));
    xy_route #(.X(0),.Y(2),.MINIMIZED(0)) dut_b02(.dx(dx_s),.dy(dy_s),.port(p_b02));

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #50000;
        $fatal(1, "[TIMEOUT] tb_xy_route exceeded limit");
    end

    // =========================================================================
    // Main
    // =========================================================================
    integer RX, RY;
    logic [2:0] exp;

    initial begin

        // =================================================================
        // TEST 1: Exhaustive 2×2 grid — all destination combinations
        // =================================================================
        $display("[TEST] Exhaustive 2x2 behavioral routing");
        for (int dxi = 0; dxi < 2; dxi++) begin
            for (int dyi = 0; dyi < 2; dyi++) begin
                @(negedge clk);
                dx_s = dxi; dy_s = dyi;
                #1;  // combinational settle

                // (0,0)
                exp = xy_ref(dxi, dyi, 0, 0);
                check_port("2x2 (0,0)", p_b00, exp, dxi, dyi, 0, 0);
                // (1,0)
                exp = xy_ref(dxi, dyi, 1, 0);
                check_port("2x2 (1,0)", p_b10, exp, dxi, dyi, 1, 0);
                // (0,1)
                exp = xy_ref(dxi, dyi, 0, 1);
                check_port("2x2 (0,1)", p_b01, exp, dxi, dyi, 0, 1);
                // (1,1)
                exp = xy_ref(dxi, dyi, 1, 1);
                check_port("2x2 (1,1)", p_b11, exp, dxi, dyi, 1, 1);
            end
        end
        if (fail_count == 0) begin
            $display("[PASS] Exhaustive 2x2 behavioral routing (%0d checks)", check_count);
            pass_count++;
        end

        // =================================================================
        // TEST 2: Minimized matches behavioral for all 2×2 destinations
        // =================================================================
        $display("[TEST] Minimized == Behavioral for 2x2 grid");
        begin
            int prev_fail = fail_count;
            for (int dxi = 0; dxi < 2; dxi++) begin
                for (int dyi = 0; dyi < 2; dyi++) begin
                    @(negedge clk);
                    dx_s = dxi; dy_s = dyi;
                    #1;
                    check_port("min==beh (0,0)", p_m00, p_b00, dxi, dyi, 0, 0);
                    check_port("min==beh (1,0)", p_m10, p_b10, dxi, dyi, 1, 0);
                    check_port("min==beh (0,1)", p_m01, p_b01, dxi, dyi, 0, 1);
                    check_port("min==beh (1,1)", p_m11, p_b11, dxi, dyi, 1, 1);
                end
            end
            if (fail_count == prev_fail) begin
                $display("[PASS] Minimized == Behavioral for 2x2 grid");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 3: Explicit port directions — local delivery
        // =================================================================
        $display("[TEST] Local delivery (dst == router position)");
        begin
            int prev_fail = fail_count;
            // (0,0) router, dst (0,0)
            @(negedge clk); dx_s = 0; dy_s = 0; #1;
            check_port("local (0,0)", p_b00, 3'd0, 0, 0, 0, 0);
            // (1,1) router, dst (1,1)
            @(negedge clk); dx_s = 1; dy_s = 1; #1;
            check_port("local (1,1)", p_b11, 3'd0, 1, 1, 1, 1);
            if (fail_count == prev_fail) begin
                $display("[PASS] Local delivery");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 4: East routing (dx > X)
        // =================================================================
        $display("[TEST] East routing");
        begin
            int prev_fail = fail_count;
            // (0,0) router, dst (1,0) → East
            @(negedge clk); dx_s = 1; dy_s = 0; #1;
            check_port("east (0,0)->1,0", p_b00, 3'd1, 1, 0, 0, 0);
            // (0,0) router, dst (1,1) → East (X first)
            @(negedge clk); dx_s = 1; dy_s = 1; #1;
            check_port("east (0,0)->1,1", p_b00, 3'd1, 1, 1, 0, 0);
            if (fail_count == prev_fail) begin
                $display("[PASS] East routing");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 5: West routing (dx < X)
        // =================================================================
        $display("[TEST] West routing");
        begin
            int prev_fail = fail_count;
            @(negedge clk); dx_s = 0; dy_s = 0; #1;
            check_port("west (1,0)->0,0", p_b10, 3'd2, 0, 0, 1, 0);
            @(negedge clk); dx_s = 0; dy_s = 1; #1;
            check_port("west (1,1)->0,1", p_b11, 3'd2, 0, 1, 1, 1);
            if (fail_count == prev_fail) begin
                $display("[PASS] West routing");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 6: South routing (dx==X, dy > Y)
        // =================================================================
        $display("[TEST] South routing");
        begin
            int prev_fail = fail_count;
            @(negedge clk); dx_s = 0; dy_s = 1; #1;
            check_port("south (0,0)->0,1", p_b00, 3'd3, 0, 1, 0, 0);
            @(negedge clk); dx_s = 1; dy_s = 1; #1;
            check_port("south (1,0)->1,1", p_b10, 3'd3, 1, 1, 1, 0);
            if (fail_count == prev_fail) begin
                $display("[PASS] South routing");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 7: North routing (dx==X, dy < Y)
        // =================================================================
        $display("[TEST] North routing");
        begin
            int prev_fail = fail_count;
            @(negedge clk); dx_s = 0; dy_s = 0; #1;
            check_port("north (0,1)->0,0", p_b01, 3'd4, 0, 0, 0, 1);
            @(negedge clk); dx_s = 1; dy_s = 0; #1;
            check_port("north (1,1)->1,0", p_b11, 3'd4, 1, 0, 1, 1);
            if (fail_count == prev_fail) begin
                $display("[PASS] North routing");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 8: X-direction priority — dx≠X always uses E/W, not N/S
        // =================================================================
        $display("[TEST] X-direction priority over Y");
        begin
            int prev_fail = fail_count;
            // Router (0,0): dst (1,1) → must go East NOT South
            @(negedge clk); dx_s = 1; dy_s = 1; #1;
            check_port("x-prio (0,0)->(1,1)", p_b00, 3'd1, 1, 1, 0, 0);
            // Router (1,1): dst (0,0) → must go West NOT North
            @(negedge clk); dx_s = 0; dy_s = 0; #1;
            check_port("x-prio (1,1)->(0,0)", p_b11, 3'd2, 0, 0, 1, 1);
            if (fail_count == prev_fail) begin
                $display("[PASS] X-direction priority over Y");
                pass_count++;
            end
        end

        // =================================================================
        // TEST 9: 3×3 grid — additional router positions
        // =================================================================
        $display("[TEST] 3x3 grid routing (behavioral)");
        begin
            int prev_fail = fail_count;
            // All 4 destination combinations for coords that fit in 2-bit
            for (int dxi = 0; dxi < 4; dxi++) begin
                for (int dyi = 0; dyi < 4; dyi++) begin
                    @(negedge clk);
                    dx_s = dxi[1:0]; dy_s = dyi[1:0];
                    #1;
                    // Check routers that are within 3×3 (X,Y ≤ 2)
                    exp = xy_ref(dxi, dyi, 2, 2);
                    check_port("3x3 (2,2)", p_b22, exp, dxi, dyi, 2, 2);
                    exp = xy_ref(dxi, dyi, 1, 2);
                    check_port("3x3 (1,2)", p_b12, exp, dxi, dyi, 1, 2);
                    exp = xy_ref(dxi, dyi, 2, 1);
                    check_port("3x3 (2,1)", p_b21, exp, dxi, dyi, 2, 1);
                    exp = xy_ref(dxi, dyi, 2, 0);
                    check_port("3x3 (2,0)", p_b20, exp, dxi, dyi, 2, 0);
                    exp = xy_ref(dxi, dyi, 0, 2);
                    check_port("3x3 (0,2)", p_b02, exp, dxi, dyi, 0, 2);
                end
            end
            if (fail_count == prev_fail) begin
                $display("[PASS] 3x3 grid routing");
                pass_count++;
            end
        end

        // =================================================================
        // RESULTS
        // =================================================================
        $display("[INFO] Total checks performed: %0d", check_count);
        if (fail_count == 0)
            $display("[RESULT] tb_xy_route: ALL %0d TESTS PASSED", pass_count);
        else begin
            $display("[RESULT] tb_xy_route: %0d PASSED, %0d FAILED", pass_count, fail_count);
            $fatal(1, "tb_xy_route FAILED");
        end
        $finish;
    end

endmodule
