# Verification scope and evidence

## Reproducible checks

`make test` must return zero, not merely print a PASS earlier in its log.
`make benchmark` and `make synth` produce optional measured comparisons.
Saved report snapshots are separate from a fresh run's `build/` outputs.

The Python model uses independent queue/state transition code. At each cycle,
the RTL trace is compared against predicted source-ready signals, sink-valid
signals, and every valid sink flit, including stalled flits. Cases cover 120
variable-size packets per configuration, local delivery, edge routes,
contention, a 200-cycle blocked sink, credit exhaustion, simultaneous
send/credit returns, and complete drainage. Both pipelines and both logic
implementations run for 2×2 and 3×3 meshes. The model additionally checks credit
conservation at every edge and checks payloads, ordering and packet boundaries.

AXI tests deliberately send AW before W and W before AW, apply partial and
zero write strobes, hold BREADY/RREADY low and verify stable responses, overlap
read/write requests, inject uniform background traffic, check DECERR, reset
with a partial write, and verify recovery. Both pipelines run this test.

The firmware is built by GCC with `-march=rv32i -mabi=ilp32`; instruction fetch,
stack, loads and stores all cross the NoC. There is no private instruction RAM
that could hide a broken network. The SoC test checks the exit code, trap flag,
statistics activity and a bit-level 8N1 decode of every emitted UART byte.
The core also runs 25 directed instruction/result checks under variable memory
latency, with separate misalignment and unsupported-extension fault checks.
These tests do not replace a RISC-V architecture compliance suite.

Hardware traffic tests check no loss, no duplicates, valid destinations,
three-flit framing and exact body data under downstream stalls. They exercise
both uniform and hotspot configuration, then disable and drain the network.

## Formal artifacts

`formal/check.py` provides explicit-state CTL fixed-point algorithms and calls
Yosys SAT temporal induction on actual RTL. It exits nonzero if a claim fails.
No bounded test is presented as an unbounded RTL proof.

| Property | Method and scope | Assumptions |
| --- | --- | --- |
| Grant mutual exclusion and request qualification | Actual `rr_arbiter` RTL induction; exhaustive CTL abstraction input masks | Initial synchronous reset, valid five-input arbiter configuration |
| A persistent request waits fewer than five advanced grants | Actual arbiter RTL induction with a wait counter | Request stays asserted during its wait; only accepted service advances priority |
| `AG(AF(served_0))` | Exhaustive CTL on round-robin service-opportunity abstraction | Request 0 persistent; finite packet ownership; eventual downstream service opportunities |
| FIFO occupancy and credits bounded 0..4, no under/overflow, conservation | Actual `noc_fifo` plus sender credit controller RTL induction | Push consumes a credit; pop requires a nonempty receiver; common reset |
| XY has no channel dependency cycle | Enumerate every source/destination route for 2×2, 3×3, 4×4 and topologically sort | Legal coordinates, X before Y, no virtual channels or extra link resources |
| `AG(AF(all_done))` | CTL on a finite four-packet channel-resource model under XY | Finite packets, receptive sinks, each abstract transition is a progress opportunity |
| Mixed XY/YX can deadlock | Reachable CTL resource counterexample plus actual RTL fixed-point trace | Experimental `ALLOW_MIXED=1`; four simultaneous eight-flit packets |

The CTL implementation uses the greatest fixed point for `AG` and least fixed
point for `AF`; paths are universally quantified over all represented
successors. Dead ends are represented with self-loops. The arbiter abstraction
permits every competing request mask while request 0 remains asserted. It
collapses stalls into service opportunities. This is a fairness abstraction,
not a claim that a permanently blocked output eventually sends a packet.

The resource model acquires a channel, acquires the next, then releases both.
Acquisition abstracts filling a four-flit input buffer with a finite long
packet. It is useful for the dependency theorem and counterexample, but is
not a cycle-exact representation of all RTL pipeline states. In particular,
the full SoC is not exhaustively model checked for temporal delivery.

## Conditional deadlock and starvation argument

Within each physical mesh, XY only permits monotonic X traversal followed
by monotonic Y traversal; it never returns from Y to X. A directed channel
cannot be re-entered in the opposite dimension order. The enumerated channel
dependency graph is therefore acyclic. Request and response meshes use
disjoint resources, eliminating request-response channel cycles.

For a finite well-formed packet, output ownership ends at the tail. At a
receptive sink, credits eventually return. Following blocked-channel
dependencies in an acyclic graph must terminate at an output that can
eventually drain. Round-robin then grants any persistent eligible requester
within at most five completed packet service opportunities. This composes to
conditional routing progress under the following environmental obligations:

1. Every accepted header eventually receives its finite body and tail.
2. Destination endpoints eventually consume complete packets and responses.
3. Clock/reset remain live, links preserve flits/credits, and coordinates are valid.
4. Injectors obey credits; no malformed packets or mid-packet routing changes occur.
5. Liveness is measured for persistent requests across eventual credit-enabled
   opportunities, not for a requester that continuously withdraws its request.

No fixed cycle bound follows if an endpoint may wait arbitrarily long. No
unconditional starvation freedom is claimed for AXI read arbitration under
an unbounded stream of prioritized writes. That is distinct from router
round-robin fairness.

## Actual RTL deadlock trace

`make formal` runs `tb_deadlock` twice. The unsafe experiment permits the
header's bit 36 to choose YX on selected packets, so the network collectively
allows all turn directions. Each source sends an eight-flit packet:

| Source → destination | Path | Held output while blocked |
| --- | --- | --- |
| 0 → 3 | East, South (XY) | Router 0 East |
| 1 → 2 | South, West (YX) | Router 1 South |
| 3 → 0 | West, North (XY) | Router 3 West |
| 2 → 1 | North, East (YX) | Router 2 North |

Each local packet retains its first output while the downstream input fills.
Those downstream headers request outputs already owned by the next local
packet. Four input buffers reach occupancy four, the four sending credits
reach zero, and no router can transfer. The test checks that fixed state for
100 more cycles and records `build/deadlock.vcd`. As all four owners wait for
credits that require one of those same blocked transfers, the fixed point
persists without an external reset; this is a cyclic wait, not just a finite
congestion timeout. With `ALLOW_MIXED=0`, the same traffic drains all 32 flits.

The production SoC does not expose the unsafe mode. The deadlock experiment
is deliberately failing network behavior and is reported separately from
passing XY tests.

