# Research and experiments

## Selected improvement

Robert Mullins, Andrew West and Simon Moore, **“Low-latency virtual-channel
routers for on-chip networks,”** Proceedings of the 31st Annual International
Symposium on Computer Architecture (ISCA), 2004, pp. 188–199, is the reference
for examining router pipeline latency and timing trade-offs. This project
implements a deliberately smaller, pipeline-reduction experiment inspired by
that work: combine header detection and XY route computation in the IDLE
stage. It does not reproduce that paper's virtual-channel/speculative router.

The baseline remains the explicit four-state pipeline. `FAST=1` removes one
header cycle per router while retaining exactly the same routes, buffers,
flit format, output reservations and credit protocol. This makes cycle-level
comparisons meaningful and leaves the channel dependency argument unchanged.
The merged stage can affect critical path, so a lower cycle count is not
automatically lower time latency after FPGA placement.

Other useful references are W. J. Dally and C. L. Seitz, **“Deadlock-Free
Message Routing in Multiprocessor Interconnection Networks,”** IEEE
Transactions on Computers, 36(5), 1987, pp. 547–553, for dependency analysis;
and C. J. Glass and L. M. Ni, **“The Turn Model for Adaptive Routing,”** ISCA
1992, pp. 278–287, for restricted-turn adaptive routing. The latter is more
complex here: adaptive routes change the allocator and the dependency proof.
Speculative allocation also needs rollback on failed credit/resource checks.
Those algorithms are discussed as alternatives, not claimed implementations.

## ESPRESSO and BDD block

`scripts/logic_opt.py` enumerates 256 rows for a generic two-bit-coordinate
XY route function, and 256 rows for five requests plus a three-bit RR pointer.
It minimizes each output using PyEDA's ESPRESSO, constructs reduced BDDs, and
checks all rows against direct behavioral functions with both evaluators.
It emits the checked-in `rtl/logic_minimized.sv`.

The variable order is coordinate bits x, y, dx, dy (low to high); RR uses
request bits before pointer bits. BDD size depends on order. Invalid RR
pointer values (5–7) return no grant in the generated block; reset and normal
updates keep the real pointer in 0–4. `MINIMIZED=1` selects the generated
blocks in the actual router. Full-mesh cycle comparisons verify integration.
The physical SoC defaults to the behavioral block unless extended to select
the minimized option; `make synth` measures the option on an isolated router.

The comparison uses a bounded-width behavioral RR arithmetic implementation,
not a deliberately oversized 32-bit index. FPGA mapping can still find
different logic for the equivalent functions. Report actual LUT/storage
mapping without assuming that ESPRESSO must outperform vendor synthesis.

## Traffic measurement

`python3 -m model.benchmark` runs a 2×2 network for 3000 cycles, excluding the
first 500 cycles from the measurement window. Three-flit packets are generated
independently at each source with probability `offered_flits_per_cycle / 3`.
The source queues are unbounded; congestion does not silently discard offered
traffic. Two fixed seeds, 7 and 19, are used for each rate and router variant.
The traffic-generation random stream does not depend on credit availability,
so both variants receive identical workloads.

Uniform traffic excludes the source. For hotspot traffic, nonzero sources
choose node 0 with 80% probability, otherwise a uniform remote destination
(which may also be node 0). Source 0 chooses a uniform remote destination.

CSV columns distinguish offered, accepted and delivered flit rates, all per
node per cycle. Accepted-header-to-consumed-tail latency includes network
stalling but excludes source queue wait. Generation-to-tail latency includes
that wait. Population variance is computed from individual measured packet
latencies. Curves average the two seed-level means. Each run reports source
backlog, outstanding packets and measured sample count, then drains all
generated traffic and checks conservation/uniqueness.

The finite observation window censors packets still pending at its end; the
backlog columns expose this. Near saturation, source-queue latency grows
without a steady-state finite mean. The peak measured throughput is reported
as **observed**, not a mathematical saturation bound or a precise threshold.
For a final report, increase duration/seeds and present uncertainty and queue
growth alongside throughput. The raw network curves do not include the SoC's
iterative statistics engine or the serialized AXI endpoint limits.

## Hardware measurements

`make synth` maps a standalone center router (X=Y=1), 64-bit flits and depth
four to generic Xilinx 7-series cells using Yosys/ABC. Both pipeline variants
and the baseline ESPRESSO option use the same flow. Report LUT cells, FFs,
distributed RAM primitives and carry/mux resources, not an invented chip area.

Actual LUT packing, placement, routing, achievable clock, BRAM/DSP mapping and
power require Vivado on the chosen part. `fpga/router_compare.tcl` supplies
matched implementation constraints. Fmax values remain null in the current
JSON reports. No area/Fmax plots with fabricated data are generated.

