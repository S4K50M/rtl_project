# Acceptance matrix

The uploaded image takes precedence over the expanded master prompt.

| Image requirement | Artifact/evidence | Status |
| --- | --- | --- |
| 2×2 mesh, stretch 3×3; five-port wormhole XY | `rtl/noc_router.sv`, `noc_mesh.sv`, eight model/RTL configuration comparisons | Implemented and simulated |
| Four-flit buffers and credit flow control | `noc_fifo`, `noc_endpoint`, router credit accounting, inductive conservation proof | Implemented and checked |
| Round-robin separable allocator | Deterministic input requests plus independent RR output arbiters, tail ownership | Implemented and checked |
| AXI4-Lite packet NIs | Host/target bridges and AXI directed/randomized data tests | Implemented; normal-access attributes fixed |
| Replace VL326 shared bus; core/memory/UART/timer nodes | Standalone RV32I NoC SoC with all four endpoints | Standalone integration passes; original VL326 source unavailable |
| Cycle-level Python golden model | `model/network.py`, exact RTL trace comparisons | Implemented and checked |
| Welford statistics from hand-written HLS | `hls/welford.cpp`, manually scheduled fixed-point RTL, numerical tests | C++/RTL verified; Vitis synthesis pending |
| IDLE/ROUTE/ACTIVE/WAIT_CREDIT FSM | Per-input router state | Implemented and exercised |
| ESPRESSO/BDD RR and XY logic | `scripts/logic_opt.py`, `rtl/logic_minimized.sv` | Minimized, exhaustively checked, integrated and mapped |
| Selectable-rate/pattern traffic generators | `traffic_source`, `traffic_client`, firmware control registers | Implemented and checked |
| Research paper implementation | Pipeline reduction inspired by Mullins/West/Moore ISCA 2004 | Implemented, separately simulated and benchmarked |
| RV32 software executes over NoC | Compiled firmware, directed ISA checks, UART decode, exit-code checks | Verified in RTL simulation |
| Latency/injection curves, uniform/hotspot | Seeded CSV and SVG plots | Measured in the RTL-validated model |
| CTL mutual exclusion/starvation freedom | Finite abstraction CTL plus actual RR RTL induction | Verified within documented assumptions/scope |
| Unrestricted-turn deadlock counterexample | Reachable abstract trace and actual mixed XY/YX RTL fixed point with XY control | Reproduced |
| Router area/Fmax baseline and paper design | Yosys 7-series router mapping; matched Vivado implementation script | Mapped area available; board Fmax pending |
| Live traffic and UART statistics demo | Real firmware enables background clients and prints counters/mean/variance | Verified through simulated UART pin; physical board pending |

## Remaining physical acceptance sequence

1. Supply the exact board/part, clock and pin constraints; confirm UART wiring.
2. Execute XSim, full Vivado synthesis and HLS synthesis on that toolchain.
3. Check full-system fit, DRC, unconstrained paths, setup and hold timing.
4. Generate/program a bitstream and capture UART output/ILA activity.
5. Run matched router implementation sweeps to report measured Fmax and area.
6. Integrate the original core/bus/peripherals when their source is available,
   and rerun the original RV32 software as the bus-replacement acceptance test.

These are unresolved external/tool/hardware steps, not passing deliverables.
