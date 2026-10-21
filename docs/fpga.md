# FPGA flow and integration

## Inputs still required

The image specifies a SoC interconnect, not an FPGA board. The optional master
prompt mentions several different Zybo boards. No exact board revision, part,
oscillator frequency, UART wiring or legacy SoC was supplied. Accordingly:

- No XDC package pins or FPGA resource capacity are fabricated.
- No FPGA part is the default in the vendor build scripts.
- The `CLK_HZ=50000000` RTL default is a parameter, not a claim about a board.
- The ARM processing system is not used instead of the RV32 soft core.
- Existing VL326 protocol details must be examined before claiming replacement.

Provide the exact FPGA part, the manufacturer master XDC/manual for that
board revision, and the original SoC source to finish those integrations.

## Simulate, synthesize, place, route

The checked portable flow uses Icarus for RTL simulation and Yosys for
elaboration/7-series router mapping. Vivado and Vitis HLS are not installed in
the cloud machine. The following vendor scripts are supplied but have not
been executed here:

```sh
make firmware
vivado -mode batch -source fpga/xsim.tcl
vivado -mode batch -source fpga/build.tcl -tclargs ACTUAL_PART /absolute/board.xdc ACTUAL_CLOCK_HZ 0
vivado -mode batch -source fpga/router_compare.tcl -tclargs ACTUAL_PART PERIOD_NS
```

`build.tcl` synthesizes the full demo, reports hierarchical utilization,
optimizes, places, routes, and writes DRC, methodology, timing and I/O reports.
It requires an actual XDC and checks every external port's package pin and
I/O standard. It rejects setup/hold failure before bitstream generation.
The script intentionally does not downgrade NSTD/UCIO DRC errors.

The physical wrapper exposes `clk`, active-low `reset_n`, and `uart_tx` only.
Confirm the board oscillator can clock PL directly. If the board needs an
MMCM/Clock Wizard or PS-provided clock, add a board-specific wrapper and use
the measured/generated fabric clock for `CLK_HZ`. UART baud is derived from
that parameter by an integer divider. Verify baud error at the chosen clock.
Reset asserts asynchronously and deasserts after two clock edges. All other
logic is in this one domain; no implicit clock-domain crossings are present.

The XDC must set the clock, reset and TX package pins and I/O standards from
the real board. Declare a clock matching `CLK_HZ`. Constrain synchronous I/O
against actual external timing; use justified asynchronous reset exceptions
only to the reset synchronizer. Do not false-path router/CPU paths to force
timing closure. Inspect unconstrained paths and clock interaction reports.

For a GUI RTL project, add `rtl/*.sv`, put `rtl/` in include directories,
select `noc_board_top`, set its clock/baud parameters, and include the actual
board XDC. Generate firmware first; `soc_target` uses `build/firmware.hex` for
RAM initialization. Run from the repository root or override `MEM_FILE` to
an absolute path. XSim's Tcl uses an absolute testbench memory parameter to
avoid simulator-directory differences.

`router_compare.tcl` uses identical part, clock period, I/O budgets and
placement steps for each design. Save LUT/FF/BRAM/DSP counts and critical
paths. To establish Fmax, sweep periods and repeat implementation until both
setup and hold pass, preserving constraints and seeds. An area estimate or
RTL cycle reduction does not establish achievable Fmax or nanosecond latency.

## Resource and timing risks

A router stores 5×4×64 = 1280 flit bits plus counters, route/FSM state and
ownership. Distributed RAM is appropriate for these shallow queues. The SoC
has eight routers because requests and responses are separate. RAM is 16 KiB
and the multicycle core's register file is 32×32 bits. The Welford engines
share iterative division hardware and use fixed-point multiplication; inspect
DSP mapping and the multiply/accumulate critical path. Pipeline that path if
the selected frequency requires it, preserving ready/valid behavior.

The open-source router mapping in `results/` excludes core, NIs, statistics,
peripherals and board I/O. Multiplying that result by eight is only a rough
lower-bound planning exercise; it cannot prove full-board fit. Vivado can map
the shallow storage and logic differently. A small part may require the
minimized logic, smaller debug instrumentation or a larger FPGA. Do not change
the required four-flit buffers or XY routing merely to fit.

## HLS

```sh
FPGA_PART=ACTUAL_PART HLS_CLOCK_NS=ACTUAL_PERIOD vitis_hls -f hls/run.tcl
```

The C++ source specifies a sample-level fixed-point calculation. The supplied
RTL manually schedules it with a shared divider. Actual Vitis output may
choose a different latency/interface. Before replacing the RTL, use its
reported latency/II, provide an adapter to `valid/ready`, rerun fixed-point
tests, and rerun SoC tests. Do not assume pin compatibility with exported IP.

## Program and demonstrate

Only after valid part/constraints, DRC and timing checks pass:

```sh
vivado -mode batch -source fpga/program.tcl -tclargs build/vivado/noc.bit
```

Connect board power/JTAG as its manual specifies. The programming script
expects exactly one detected FPGA; with a scan chain select the intended
device explicitly. Open a UART terminal at 115200, 8 data bits, no parity,
one stop bit, no flow control. A PL UART might require an external USB-UART
adapter if the board's onboard USB-UART is connected only to PS pins.

Expected firmware output includes `MEMORY PASS`, `TIMER PASS`, nonzero and
equal live injected/delivered counts, Q16 mean/variance, and `SYSTEM PASS`.
These are expected **physical acceptance criteria**; current matching output
comes from RTL simulation and the bit-level UART decoder, not a board.

For ILA, probe request/response link valid/flit/credit signals, FIFO occupancy,
router ownership/FSM state, host NI state, CPU PC/trap, and traffic errors.
Trigger on prolonged zero credits, an unsupported response, or CPU trap. ILA
is optional and consumes resources; include its cost in final area/timing.

## Replace a supplied legacy SoC bus

1. Identify the actual core's fetch/data interfaces, reset vector, byte enables,
   response/error handling and number of outstanding transactions. Do not infer
   an AXI interface from the name VL326.
2. For a native core interface, replace `rv32_axi_adapter` with an appropriate
   protocol adapter, or use the original core's AXI4-Lite master directly.
3. Connect that master to `noc_soc_fabric`; replace `soc_target` instances with
   the original memory, UART and timer slaves at the matching target NIs.
4. Adapt address decoding to the real firmware map, retaining separate request
   and response networks and finite response buffering.
5. Run the old firmware/bus tests before and after integration, then repeat
   the NoC/AXI tests and physical bring-up. Compare bus and NoC on the same
   core, memories, frequency and workload, including the NoC's extra area.

For four nodes, a mesh can have higher zero-load latency than a bus. Its
benefit is independent simultaneous paths under contention, not guaranteed
speedup on a serialized CPU workload. No bus comparison is invented without
the original implementation.

