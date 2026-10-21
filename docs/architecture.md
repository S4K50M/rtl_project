# Architecture

## Topology and storage

Node ID is `y*NX+x`; x increases east and y increases south. The port order is
local=0, east=1, west=2, south=3, north=4. Mesh links connect opposite ports.
All links and endpoints share one clock and reset. Input buffers register every
hop; there are no combinational data bypasses between routers. Invalid edge
inputs are tied off. Callers must supply valid destination coordinates.

`noc_mesh` accepts `NX`, `NY`, `DEPTH`, `FAST`, and `MINIMIZED`. Coordinates
are two bits; 2×2 and 3×3 meshes are tested. The default depth is four; pointer
wrap in `noc_fifo` explicitly supports non-power-of-two depths too. Shallow
FIFOs infer registers or distributed RAM, depending on the synthesis tool.

`noc_endpoint` converts a ready/valid stream into the local credit interface,
and supplies a four-flit ejection FIFO. A ready/valid source must hold its flit
while blocked. A raw credit source must send only while it has capacity.

## Packet format

All flits are 64 bits. Header fields are meaningful only when HEAD=1; body
flits carry the payload and tail marker.

| Bits | Field |
| --- | --- |
| 63 | HEAD |
| 62 | TAIL; HEAD+TAIL denotes a one-flit packet |
| 61:60, 59:58 | Destination x, y |
| 57:56, 55:54 | Source x, y |
| 53:51 | Operation: read request=0, write request=1, read response=2, write response=3 |
| 50:43 | Transaction tag |
| 42:39 | Write byte strobes |
| 38:37 | AXI response code |
| 36 | Test-only mixed-routing selector; ignored with `ALLOW_MIXED=0` |
| 35:32 | Reserved |
| 31:0 | Address, write data, response data, or traffic payload |

A write has an address header followed by a data tail. A read request and
each response occupy one flit. A single global outstanding transaction at each
host preserves ordering; source coordinates and tags identify its response.
The address map selects the destination, and endpoint decode errors return
AXI DECERR (`11`). Successful accesses return OKAY (`00`).

Generic mesh tests use packets of 1–11 flits to exercise wormhole behavior
beyond the four-flit buffer depth. Bodies keep the route selected by the header.
Output reservation lasts from the first granted flit until the tail. A
stalled or temporarily empty owning input retains its reservation; other
packets cannot interleave into it.

## Router timing and allocation

`IDLE` detects a buffered header. Baseline `ROUTE` then latches the XY output.
`ACTIVE` requests that output. Zero downstream credits cause `WAIT_CREDIT`;
arbitration contention leaves the input active. WAIT_CREDIT returns to ACTIVE
when credits are available. A sent tail returns the input to IDLE. A packet
with no buffered body flit simply waits while retaining its route/ownership.

Input selection is separable and trivial here: each input has one queue and
one deterministic output request. Five output round-robin arbiters resolve
contention independently, allowing up to five nonconflicting transfers per
cycle. This is not a multi-VC allocator. Priority advances after each actual
flit transfer; at packet release it points after the previous owner. Packet
reservation dominates the arbiter while a body is in flight.

`FAST=1` computes/latches the route directly in IDLE, removing the ROUTE cycle.
It does not change the path, buffering, allocator, or credit protocol. For a
one-flit corner-to-corner transfer through three routers, accepted injection
to consumed ejection is 10 baseline cycles or 7 fast cycles. Thus each router
needs 3 baseline or 2 fast cycles from buffered header to first transmission,
plus endpoint consumption. Body flits can transfer on successive cycles.

All flit transfers and returned credits are sampled on the same rising edge.
A credit counter is initialized to DEPTH, decremented on send, incremented on
downstream pop, and unchanged on simultaneous send/return. The same-cycle
return does not permit a send when the pre-edge credit is zero. Link pipeline
registers are not present; adding them requires tracking in-flight credits.
For the current links, `sender_credit + receiver_occupancy == DEPTH`.

There are no virtual channels. Head-of-line blocking is expected. A source
that never supplies its tail, a destination that never drains, or an illegal
destination can prevent delivery; the liveness claims exclude those cases.

## AXI4-Lite integration

`axi_noc_host` separately holds AW and W until both are present. A read can
start when there is no partial write. The implementation serializes reads
and writes globally and gives a completed/partial write precedence. B and R
payloads remain stable until accepted. There are no bursts or AXI IDs.
AWPROT/ARPROT attributes are fixed normal accesses and are not transported;
an integration wrapper must tie/ignore those attributes as appropriate for
the supplied SoC. This fabric does not implement an access-control boundary.

`axi_noc_target` independently handshakes AW and W at the peripheral, waits
for B/R, and sends a response to the source coordinates. Request and response
networks have separate FIFOs, credits, and physical links. Each target can
always eventually emit a response independently of new request reception.

| Region/register | Meaning |
| --- | --- |
| `0x00000000`–`0x00003fff` | 16 KiB RAM at node 1; firmware, data, and stack |
| `0x10000000` write byte lane 0 | UART transmit; target waits for transmitter availability |
| `0x10000004` read | UART ready bit 0 |
| `0x10000010` | CPU completed transaction sample count |
| `0x10000014` | CPU mean latency Q16.16 |
| `0x10000018` | CPU population variance Q16.16 |
| `0x10000020` read/write | Traffic control: enable bit 0, hotspot bit 1, rate threshold bits 31:16 |
| `0x10000024` | Total background reads injected (nodes 1–3) |
| `0x10000028` | Total background responses delivered |
| `0x1000002c` | Node 2 background read mean Q16.16 |
| `0x10000030` | Node 2 background population variance Q16.16 |
| `0x10000034` | Background tag/op/response errors |
| `0x20000000` read | Free-running 32-bit cycle timer, modulo wrap |
| `0x20000004` write all byte lanes | Demo exit code and sticky done flag |

Unmapped and unaligned peripheral accesses return DECERR. The CPU handles
aligned word bus addresses with byte-lane extraction/sign extension and write
strobes for byte/halfword operations; misaligned halfword/word instructions
trap. RAM persists over fabric reset; protocol state, counters and clients reset.

## Statistics

`hls/welford.cpp` is the hand-written HLS algorithm. `welford_stats.sv` is its
hand-scheduled fixed-point implementation; it is **not described as a Vitis
generated artifact**. C++ and RTL are independently compared to numerical
expectations. `hls/run.tcl` enables actual Vitis synthesis when available.

For each valid accepted sample: `n += 1`, `delta=x-mean`,
`mean += trunc(delta/n)`, `M2 += (delta*(x-mean)) >> 16`.
Mean and M2 use Q16 scaling; population variance is `M2/n`. Input latencies
clamp to 32767 cycles, count saturates at 65535, and the published variance
saturates at `0xffffffff` (Q16.16). Reset starts a new observation window.
Quantization means results differ slightly from floating-point Welford.

One shared iterative 64/32 divider runs the mean and variance calculations.
The engine backpressures input until it commits all three outputs together.
The host and traffic clients gate response consumption on engine readiness;
samples are not silently dropped. This deliberately trades measurement
throughput for area. CPU statistics include packetization/target/response and
endpoint waiting time; background-client statistics measure read round trips.
They are not the raw one-way latency plotted by the network model.

The benchmark mesh has no statistics backpressure. Comparing SoC throughput
against raw-router throughput would require accounting for this difference.
For higher rate measurement, a pipelined HLS unit or a specified decimation
scheme with a dropped-sample count would be a separate optimization.

## Hardware traffic

`traffic_source` emits three-flit packets directly into a mesh. Its LFSR,
idle-cycle threshold and destination rejection sampling provide repeatable
uniform-remote and hotspot patterns. Invalid/self destination candidates are
rejected, so the threshold is not itself the offered flit rate. Accepted flit
counts must be used for throughput. A live packet finishes after disable.

`traffic_client` uses the real SoC request and response NIs. It issues one
outstanding synthetic read per node, either among all three target nodes or
to the memory hotspot. Disabling prevents new transactions, then pending
transactions drain. Uniform selection rejects one of four 2-bit candidates.
The firmware demonstrates hotspot mode; the AXI test exercises uniform mode.

