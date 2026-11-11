`timescale 1ns/1ps
// FAST=1 six-scenario integration test.
// Reuses all assertions and exact low/medium/high + uniform/hotspot settings
// in tb_traffic, so the comparison changes ONLY the router FAST parameter.
// IMPORTANT: Use +PACKETS=... +CYCLES=... +SUMMARY=... to preserve baseline CSVs.
module tb_traffic_fast;
    tb_traffic #(
        .NX(2), .NY(2), .FAST(1),
        .WARMUP_CYCLES(2000),
        .MEASURE_CYCLES(10000),
        .MAX_DRAIN_CYCLES(15000)
    ) fast_benchmark();
endmodule
