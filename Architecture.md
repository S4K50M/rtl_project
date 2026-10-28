# Architecture — 2×2 Mesh Network-on-Chip SoC

> **Project:** P15 — 2-D Mesh NoC with Verified Deadlock Freedom  
> **Topology:** 2×2 (extensible to 3×3) wormhole mesh, XY routing, credit-based flow control  
> **Interconnect:** Replaces shared bus (VL326) with a NoC; nodes carry RV32 CPU, RAM, UART/stats, and timer

---

## Table of Contents

1. [Repository Layout](#1-repository-layout)  
2. [Module Hierarchy Diagram](#2-module-hierarchy-diagram)  
3. [Module Catalogue](#3-module-catalogue)  
   - 3.1 [Global Definitions](#31-global-definitions)  
   - 3.2 [NoC Fabric — Core Primitives](#32-noc-fabric--core-primitives)  
   - 3.3 [NoC Fabric — Router Datapath](#33-noc-fabric--router-datapath)  
   - 3.4 [NoC Fabric — Mesh Interconnect](#34-noc-fabric--mesh-interconnect)  
   - 3.5 [Network Interface (NI) — AXI4-Lite Bridge](#35-network-interface-ni--axi4-lite-bridge)  
   - 3.6 [Processor Subsystem](#36-processor-subsystem)  
   - 3.7 [SoC Peripherals](#37-soc-peripherals)  
   - 3.8 [Traffic Generation & Measurement](#38-traffic-generation--measurement)  
   - 3.9 [Latency Statistics Unit (HLS-derived)](#39-latency-statistics-unit-hls-derived)  
   - 3.10 [Top-Level Integration](#310-top-level-integration)  
   - 3.11 [Minimized Logic (ESPRESSO/BDD)](#311-minimized-logic)  
4. [File → Module Mapping (Quick Reference)](#4-file--module-mapping-quick-reference)  
5. [Testbench Coverage Map](#5-testbench-coverage-map)  
6. [Formal Verification Harnesses](#6-formal-verification-harnesses)  
7. [Non-RTL Support Files](#7-non-rtl-support-files)  

---

## 1. Repository Layout

```
rtl_project/
├── rtl/                   # Synthesizable RTL (SystemVerilog)
│   ├── noc_defs.vh        # Global flit-field macros (header)
│   ├── noc_fifo.sv        # Parameterised circular FIFO
│   ├── rr_arbiter.sv      # Round-robin separable allocator
│   ├── xy_route.sv        # XY destination-port decoder
│   ├── logic_minimized.sv # ESPRESSO-minimized combinational blocks
│   ├── noc_router.sv      # 5-port wormhole router (instantiates all above)
│   ├── noc_mesh.sv        # 2×2 (NX×NY) mesh of routers
│   ├── noc_endpoint.sv    # Credit↔ready/valid bridge at each local port
│   ├── axi_noc_host.sv    # AXI4-Lite master → NoC packet (initiator NI)
│   ├── axi_noc_target.sv  # NoC packet → AXI4-Lite slave (target NI)
│   ├── rv32_core.sv       # Multicycle RV32I integer core
│   ├── rv32_axi_adapter.sv# Core req/rsp ↔ AXI4-Lite
│   ├── soc_target.sv      # RAM / UART+stats / timer peripheral slave
│   ├── uart_tx.sv         # 8N1 UART transmitter
│   ├── welford_stats.sv   # Running mean/variance (hand-HLS)
│   ├── unsigned_divider.sv# 64÷32 restoring divider (used by Welford)
│   ├── traffic_source.sv  # Standalone LFSR flit injector
│   ├── traffic_client.sv  # AXI-read synthetic client + latency recorder
│   ├── noc_soc_fabric.sv  # Full SoC assembly (dual mesh + all nodes)
│   ├── noc_demo_top.sv    # CPU + adapter + fabric integration top
│   └── noc_board_top.sv   # Physical I/O wrapper for FPGA board
│
├── tb/                    # Simulation testbenches
│   ├── tb_core.sv         # RV32I ISA directed test + fault checks
│   ├── tb_axi.sv          # AXI fabric R/W stress + live traffic
│   ├── tb_mesh.sv         # Mesh trace-driven golden comparison
│   ├── tb_traffic.sv      # Hardware traffic source packet integrity
│   ├── tb_deadlock.sv     # Deadlock injection (MIXED=1) / XY control
│   ├── tb_stats.sv        # Welford RTL vs. file-driven reference
│   ├── tb_divider.sv      # Unsigned divider vector test
│   └── tb_soc.sv          # Full SoC + UART serial decode end-to-end
│
├── formal/                # Formal verification (SymbiYosys / Tabby CAD)
│   ├── credit_harness.sv  # Proof: credit invariant on noc_fifo
│   ├── rr_harness.sv      # Proof: one-hot grant + starvation bound on rr_arbiter
│   └── check.py           # SymbiYosys Python driver
│
├── model/                 # Cycle-level Python golden model
│   ├── __init__.py
│   ├── network.py         # Mesh simulator (routers, buffers, XY route)
│   └── benchmark.py       # Latency-vs-injection curves (uniform + hotspot)
│
├── hls/                   # High-Level Synthesis reference (Vitis HLS)
│   ├── welford.cpp        # C++ Welford algorithm (HLS source)
│   ├── test_welford.cpp   # HLS testbench
│   └── run.tcl            # Vitis HLS project script
│
├── firmware/              # RV32 bare-metal software
│   ├── main.c             # Traffic-test + UART print application
│   ├── start.S            # Reset vector / stack setup
│   ├── isa.S              # RV32I directed ISA test program
│   └── link.ld            # Linker script (0x0000 base, 16 KB)
│
├── fpga/                  # Xilinx Vivado/xsim scripts
│   ├── build.tcl          # Synthesis + implementation project
│   ├── xsim.tcl           # Behavioural simulation flow
│   ├── program.tcl        # Bitstream programming script
│   └── router_compare.tcl # Baseline vs. fast-router area/Fmax sweep
│
├── scripts/               # Build utilities
│   ├── elaborate.sh       # Icarus/Verilator elaboration helper
│   ├── iverilog.sh        # Icarus compilation wrapper
│   ├── vvp.sh             # vvp invocation wrapper
│   ├── synth.sh           # Yosys synthesis script invoker
│   ├── env.sh             # Environment variable setup
│   ├── setup.sh           # One-shot workspace bootstrap
│   ├── logic_opt.py       # Generates logic_minimized.sv via ESPRESSO
│   ├── bin2hex.py         # Binary → Verilog $readmemh hex converter
│   ├── synth_report.py    # Parses Yosys/Vivado area reports
│   └── snapshot_results.py# Captures timing/area into results/
│
├── docs/                  # Design documentation
├── results/               # Generated artefacts (logs, CSV, waveforms)
├── tests/                 # Python pytest integration helpers
├── Makefile               # Top-level build orchestration
└── README.md              # Project overview
```

---

## 2. Module Hierarchy Diagram

```
noc_board_top
└── noc_demo_top
    ├── rv32_core
    ├── rv32_axi_adapter
    └── noc_soc_fabric
        ├── noc_mesh [requests]          ← dual-mesh topology
        │   └── noc_router (×4, parameterised X,Y)
        │       ├── noc_fifo  (×5 input buffers per router)
        │       ├── xy_route  (×5 per router)
        │       │   └── xy_minimized [if MINIMIZED=1]
        │       └── rr_arbiter (×5 output ports per router)
        │           └── rr_minimized [if MINIMIZED=1]
        ├── noc_mesh [responses]         ← separate return-path mesh
        │   └── (same structure as above)
        ├── noc_endpoint (×4 req + ×4 rsp = 8 total)
        │   └── noc_fifo (RX FIFO)
        ├── axi_noc_host  [node 0 — CPU initiator NI]
        ├── welford_stats [node 0 — AXI-transaction latency]
        │   └── unsigned_divider
        └── [nodes 1,2,3 — peripheral nodes]
            ├── traffic_client  (×3)
            │   └── welford_stats
            │       └── unsigned_divider
            ├── axi_noc_target  (×3)
            └── soc_target      (×3 — KIND=1/2/3)
                └── uart_tx     [KIND=2 only]
```

> **Note on dual mesh:** `noc_soc_fabric` instantiates two separate `noc_mesh` networks — one for *requests* (CPU→peripherals) and one for *responses* (peripherals→CPU). Each mesh is a full 2×2 grid with independent credit state.

---

## 3. Module Catalogue

### 3.1 Global Definitions

| File | Content | Role |
|------|---------|------|
| `rtl/noc_defs.vh` | Flit-field bit-range macros (`HEAD`, `TAIL`, `DX`, `DY`, `SX`, `SY`, `OP`, `TAG`, `STRB`, `RESP`, `DATA`) and opcode constants (`RD_REQ`, `WR_REQ`, `RD_RESP`, `WR_RESP`) | Shared by all flit-handling modules; included via `` `include "noc_defs.vh" `` |

**Flit format (64 bits):**

```
Bit:  63     62     61:60  59:58  57:56  55:54  53:51  50:43  42:39  38:37  36     31:0
      HEAD  TAIL   DX[1:0] DY[1:0] SX[1:0] SY[1:0] OP[2:0] TAG[7:0] STRB[3:0] RESP[1:0] [rsvd] DATA[31:0]
```

---

### 3.2 NoC Fabric — Core Primitives

#### `noc_fifo` — Parameterised Circular FIFO

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_fifo.sv` |
| **Module** | `noc_fifo #(WIDTH=64, DEPTH=4)` |
| **Ports** | `clk`, `rst`, `push`, `pop`, `din[WIDTH-1:0]`, `dout[WIDTH-1:0]`, `empty`, `full`, `count[$clog2(DEPTH+1)-1:0]` |
| **Description** | Synchronous wrap-around FIFO with separate read/write pointers. Default depth = 4 flits (credit window). Simulation-only overflow/underflow `$fatal` assertions. |
| **Instantiated by** | `noc_router` (×5 input buffers), `noc_endpoint` (RX buffer) |
| **Testbenches** | Covered indirectly by `tb_mesh`, `tb_axi`, `tb_traffic`; formally proven via `formal/credit_harness.sv` |

#### `rr_arbiter` — Round-Robin Separable Allocator

| Item | Detail |
|------|--------|
| **File** | `rtl/rr_arbiter.sv` |
| **Module** | `rr_arbiter #(N=5, MINIMIZED=0)` |
| **Ports** | `clk`, `rst`, `advance`, `request[N-1:0]`, `grant[N-1:0]` |
| **Description** | Fixed-priority round-robin allocator. `next` pointer advances on `advance` (= outgoing flit accepted). When `MINIMIZED=1` and `N=5`, delegates to the ESPRESSO-generated `rr_minimized` combinational block inside `logic_minimized.sv`. |
| **Instantiated by** | `noc_router` — one arbiter per output port (5 instances per router) |
| **Testbenches** | `tb_mesh`, `tb_traffic` (behavioural coverage); formally proven in `formal/rr_harness.sv` |

#### `xy_route` — XY Destination-Port Decoder

| Item | Detail |
|------|--------|
| **File** | `rtl/xy_route.sv` |
| **Module** | `xy_route #(X=0, Y=0, MINIMIZED=0)` |
| **Ports** | `dx[1:0]`, `dy[1:0]` (destination coordinates from flit), `port[2:0]` (one of: 0=local, 1=East, 2=West, 3=South, 4=North) |
| **Description** | Pure combinational XY routing: route East/West first, then South/North, then local ejection. When `MINIMIZED=1`, delegates to `xy_minimized` from `logic_minimized.sv`. |
| **Instantiated by** | `noc_router` — one decoder per input port (5 instances per router) |
| **Testbenches** | Exercised by all mesh-level TBs; deadlock control scenario in `tb_deadlock` |

---

### 3.3 NoC Fabric — Router Datapath

#### `noc_router` — 5-Port Wormhole Router

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_router.sv` |
| **Module** | `noc_router #(X=0, Y=0, DEPTH=4, FAST=0, MINIMIZED=0, ALLOW_MIXED=0)` |
| **Parameters** | `X,Y` — grid coordinates; `DEPTH` — FIFO depth (= initial credit count); `FAST` — 1-cycle route lookahead (skip ROUTE state); `MINIMIZED` — use ESPRESSO logic; `ALLOW_MIXED` — enables YX+XY per-packet mixing (deadlock experiment only) |
| **Ports** | `in_flit[5×64-1:0]`, `in_valid[4:0]`, `in_credit[4:0]` (from upstream), `out_flit[5×64-1:0]`, `out_valid[4:0]`, `out_credit[4:0]` (to downstream) |
| **FSM states (per input port)** | `IDLE → ROUTE → ACTIVE ↔ WAIT_CREDIT → IDLE` |
| **Sub-instances** | 5× `noc_fifo`, 5× `xy_route`, 5× `rr_arbiter` |
| **Description** | Wormhole router with credit-based back-pressure. Each input port has a 4-state FSM. Output-port contention resolved by round-robin grant; worm ownership (lock) persists until tail flit. Credit counters track downstream buffer availability. |
| **Testbenches** | `tb_mesh.sv`, `tb_traffic.sv`, `tb_deadlock.sv` |

**Input-port FSM:**

```
     head flit present
IDLE ──────────────────► ROUTE (or ACTIVE if FAST=1)
                              │ route computed
                              ▼
                           ACTIVE ◄──────────── credit returned
                              │
                   credits==0 │
                              ▼
                        WAIT_CREDIT ──────► ACTIVE (credit > 0)
                              │
                   tail+pop   │
                              ▼
                            IDLE
```

---

### 3.4 NoC Fabric — Mesh Interconnect

#### `noc_mesh` — NX×NY Router Array

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_mesh.sv` |
| **Module** | `noc_mesh #(NX=2, NY=2, DEPTH=4, FAST=0, MINIMIZED=0, ALLOW_MIXED=0)` |
| **Ports** | `inject_flit[NX×NY×64-1:0]`, `inject_valid[NX×NY-1:0]`, `inject_credit[NX×NY-1:0]` — local injection; `eject_flit/valid/credit` — local ejection |
| **Description** | `generate` loop instantiates `NX×NY` routers and wires their inter-router ports: East port of (x,y) ↔ West port of (x+1,y); South port of (x,y) ↔ North port of (x,y+1). Boundary ports are tied to zero/unused. Port order: `[0]=local, [1]=East, [2]=West, [3]=South, [4]=North`. |
| **Sub-instances** | `NX×NY` × `noc_router` |
| **Testbenches** | `tb_mesh.sv`, `tb_traffic.sv`, `tb_deadlock.sv` |

---

### 3.5 Network Interface (NI) — AXI4-Lite Bridge

#### `noc_endpoint` — Credit ↔ Ready/Valid Adapter

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_endpoint.sv` |
| **Module** | `noc_endpoint #(DEPTH=4)` |
| **Ports** | TX side: `tx_data[63:0]`, `tx_valid`, `tx_ready`; RX side: `rx_data[63:0]`, `rx_valid`, `rx_ready`; Mesh side: `inject_flit/valid/credit`, `eject_flit/valid/credit` |
| **Description** | Translates the internal `valid/ready` stream from NI modules into the mesh's credit protocol. Maintains a local credit counter for TX; buffers incoming ejected flits in a `noc_fifo`. |
| **Sub-instances** | 1× `noc_fifo` (RX) |
| **Instantiated by** | `noc_soc_fabric` (8 instances: 4 for request mesh + 4 for response mesh) |
| **Testbenches** | `tb_mesh.sv`, `tb_deadlock.sv`, `tb_traffic.sv` |

#### `axi_noc_host` — AXI4-Lite Master → NoC Initiator NI

| Item | Detail |
|------|--------|
| **File** | `rtl/axi_noc_host.sv` |
| **Module** | `axi_noc_host` |
| **AXI slave ports** | `s_aw*`, `s_w*`, `s_b*`, `s_ar*`, `s_r*` (standard AXI4-Lite subordinate) |
| **NoC side** | `tx_data/valid/ready` (to `noc_endpoint`), `rx_data/valid/ready` (from `noc_endpoint`) |
| **Extras** | `sample_valid`, `sample_latency[31:0]`, `sample_ready` — latency measurement handshake to `welford_stats` |
| **FSM states** | `IDLE → HEADER → BODY → WAIT_RESPONSE → BRESP/RRESP → IDLE` |
| **Description** | Accepts one outstanding AXI4-Lite transaction. Packs it into a 1-flit (read) or 2-flit (write) packet, routes based on upper address bits (`a[31:28]`), waits for a response flit, and presents AXI B/R channels. Tracks round-trip latency in `ticks`. |
| **Instantiated by** | `noc_soc_fabric` (1 instance, node 0) |
| **Testbenches** | `tb_axi.sv`, `tb_soc.sv` |

#### `axi_noc_target` — NoC Packet → AXI4-Lite Target NI

| Item | Detail |
|------|--------|
| **File** | `rtl/axi_noc_target.sv` |
| **Module** | `axi_noc_target #(X=1, Y=0)` |
| **NoC side** | `rx_data/valid/ready` (incoming request), `tx_data/valid/ready` (outgoing response) |
| **AXI master ports** | `m_aw*`, `m_w*`, `m_b*`, `m_ar*`, `m_r*` (AXI4-Lite manager toward peripheral) |
| **FSM states** | `RX_HEADER → RX_BODY → WRITE → READ → TX → RX_HEADER` |
| **Description** | Receives request packets from the NoC, unpacks them to AXI4-Lite transactions toward the peripheral slave, captures the response, and sends a response flit back sourced from `(X, Y)`. |
| **Instantiated by** | `noc_soc_fabric` (3 instances, nodes 1, 2, 3) |
| **Testbenches** | `tb_axi.sv` |

---

### 3.6 Processor Subsystem

#### `rv32_core` — Multicycle RV32I Integer Core

| Item | Detail |
|------|--------|
| **File** | `rtl/rv32_core.sv` |
| **Module** | `rv32_core` |
| **Ports** | `req_valid/ready/write/addr/wdata/wstrb` (memory request), `rsp_valid/ready/data/error` (memory response), `halted`, `trap`, `pc[31:0]` |
| **ISA** | RV32I base (no M/C/CSR/privileges) — LUI, AUIPC, JAL, JALR, branches, ALU R/I, loads, stores, FENCE (nop), EBREAK (halt) |
| **FSM states** | `FETCH → FETCH_WAIT → EXEC → MEM → MEM_WAIT` |
| **Description** | All instruction fetches and data accesses share a single request/response port (serialised). No pipeline or virtual memory. `EBREAK` halts with `halted=1`; illegal opcode/misaligned address halts with `trap=1`. |
| **Instantiated by** | `noc_demo_top` |
| **Testbenches** | `tb/tb_core.sv` — full directed ISA test + misalignment + illegal instruction |

#### `rv32_axi_adapter` — Core req/rsp ↔ AXI4-Lite

| Item | Detail |
|------|--------|
| **File** | `rtl/rv32_axi_adapter.sv` |
| **Module** | `rv32_axi_adapter` |
| **Ports** | `req_*` (from `rv32_core`), `rsp_*` (to `rv32_core`), full AXI4-Lite manager ports |
| **FSM states** | `IDLE → WRITE/READ → RESPONSE → IDLE` |
| **Description** | Bridges the core's simple valid/ready request interface to AXI4-Lite write (AW+W+B) and read (AR+R) channels. Handles simultaneous AW/W issuance and BRESP/RRESP collection. |
| **Instantiated by** | `noc_demo_top` |
| **Testbenches** | Exercised indirectly by `tb_soc.sv` |

---

### 3.7 SoC Peripherals

#### `soc_target` — Multi-Kind Peripheral Slave

| Item | Detail |
|------|--------|
| **File** | `rtl/soc_target.sv` |
| **Module** | `soc_target #(KIND=1, WORDS=4096, MEM_FILE="build/firmware.hex", CLK_HZ, BAUD)` |
| **KIND** | `1` = RAM node (base `0x0000_0000`, 16 KB default, `$readmemh`-initialised) · `2` = UART + stats + traffic-control node (base `0x1000_0000`) · `3` = Timer + exit-code node (base `0x2000_0000`) |
| **AXI slave ports** | Standard AXI4-Lite subordinate (1-cycle latency reads, write-address+data captured independently) |
| **Extras** | `stat_count/mean_q16/variance_q16` (read-only from Welford), `traffic_enable/hotspot/rate` (traffic generator control), `uart`/`uart_event`/`uart_byte`, `done`/`exit_code` |
| **Sub-instances** | 1× `uart_tx` (instantiated only when `KIND==2`) |
| **Instantiated by** | `noc_soc_fabric` (3 instances: KIND=1 at node 1, KIND=2 at node 2, KIND=3 at node 3) |
| **Testbenches** | `tb_axi.sv` (register map), `tb_soc.sv` (full software execution) |

**Memory map (KIND=2, node 2):**

| Address | Access | Register |
|---------|--------|----------|
| `0x10000000` | W | UART TX byte (byte-enable `[0]`) |
| `0x10000004` | R | `uart_ready` |
| `0x10000010` | R | `stat_count` |
| `0x10000014` | R | `stat_mean_q16` |
| `0x10000018` | R | `stat_variance_q16` |
| `0x10000020` | R/W | Traffic control (`{rate,…,hotspot,enable}`) |
| `0x10000024` | R | `traffic_injected` |
| `0x10000028` | R | `traffic_delivered` |
| `0x1000002C` | R | `traffic_mean` |
| `0x10000030` | R | `traffic_variance` |
| `0x10000034` | R | `traffic_errors` |

#### `uart_tx` — 8N1 UART Transmitter

| Item | Detail |
|------|--------|
| **File** | `rtl/uart_tx.sv` |
| **Module** | `uart_tx #(CLK_HZ=50000000, BAUD=115200)` |
| **Ports** | `clk`, `rst`, `valid`, `data[7:0]`, `ready`, `tx` |
| **Description** | Shift-register 8N1 serialiser. Baud divider computed as `CLK_HZ/BAUD`. `ready` = idle, `tx` idles high. |
| **Instantiated by** | `soc_target` (KIND=2) |
| **Testbenches** | `tb_soc.sv` (verifies UART serial pin bit-by-bit against captured bytes) |

---

### 3.8 Traffic Generation & Measurement

#### `traffic_source` — Standalone LFSR Flit Injector

| Item | Detail |
|------|--------|
| **File** | `rtl/traffic_source.sv` |
| **Module** | `traffic_source #(NODE=0, NX=2, NY=2, SEED=32'h1)` |
| **Ports** | `clk`, `rst`, `enable`, `hotspot`, `rate[15:0]`, `data[63:0]`, `valid`, `ready`, `packets_injected[31:0]` |
| **Description** | LFSR-based Bernoulli injection: fires if `random_state[15:0] < rate`. Uniform destination by rejection-sampling. Hotspot mode: nodes ≠ 0 direct ≈81% of traffic to node 0. Generates 3-flit packets (head + 2 body/tail). |
| **Instantiated by** | `tb_traffic.sv` (×4 nodes) |
| **Testbenches** | `tb/tb_traffic.sv` |

#### `traffic_client` — AXI-Read Synthetic Client + Latency Recorder

| Item | Detail |
|------|--------|
| **File** | `rtl/traffic_client.sv` |
| **Module** | `traffic_client #(NODE=2)` |
| **Ports** | `clk`, `rst`, `enable`, `hotspot`, `rate[15:0]`; TX/RX NoC streams; `injected/delivered/errors[31:0]`; `mean_q16/variance_q16[31:0]` |
| **Description** | Issues single-flit AXI-read requests over the NoC at a Bernoulli rate, awaits responses, and feeds round-trip latency samples into an embedded `welford_stats` unit. Checks TAG, RESP, and OP fields on each response. |
| **Sub-instances** | 1× `welford_stats` |
| **Instantiated by** | `noc_soc_fabric` (×3, nodes 1, 2, 3) |
| **Testbenches** | `tb_axi.sv` (via `noc_soc_fabric`), `tb_soc.sv` |

---

### 3.9 Latency Statistics Unit (HLS-derived)

#### `welford_stats` — Welford Running Mean/Variance

| Item | Detail |
|------|--------|
| **File** | `rtl/welford_stats.sv` |
| **Module** | `welford_stats #(MAX_SAMPLES=65535)` |
| **Ports** | `clk`, `rst`, `valid`, `latency[31:0]`; `count[31:0]`, `mean_q16[31:0]`, `variance_q16[31:0]`, `ready` |
| **Description** | Hand-scheduled RTL implementation of Welford's online algorithm (C++ HLS source in `hls/welford.cpp`). Q16.16 fixed-point arithmetic. Two sequential 64÷32-bit divisions (mean update, variance update) share one `unsigned_divider` hardware unit. Outputs commit atomically after both divisions complete. Input latency clamped to 32767 cycles. |
| **Sub-instances** | 1× `unsigned_divider` |
| **FSM states** | `IDLE → MEAN_WAIT → VAR_WAIT → IDLE` |
| **Instantiated by** | `noc_soc_fabric` (1 instance for AXI host latency), `traffic_client` (3 instances for synthetic traffic) |
| **Testbenches** | `tb/tb_stats.sv` |

#### `unsigned_divider` — 64÷32 Restoring Divider

| Item | Detail |
|------|--------|
| **File** | `rtl/unsigned_divider.sv` |
| **Module** | `unsigned_divider` |
| **Ports** | `clk`, `rst`, `start`, `numerator[63:0]`, `denominator[31:0]`, `busy`, `done`, `quotient[63:0]` |
| **Description** | Non-restoring (restoring) shift-subtract divider. One quotient bit per clock cycle; 64 cycles per division. `busy` asserted during computation; `done` pulses when complete. |
| **Instantiated by** | `welford_stats` |
| **Testbenches** | `tb/tb_divider.sv` |

---

### 3.10 Top-Level Integration

#### `noc_soc_fabric` — Full SoC Assembly

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_soc_fabric.sv` |
| **Module** | `noc_soc_fabric #(FAST=0, MEM_FILE, CLK_HZ, BAUD)` |
| **AXI slave ports** | Standard AXI4-Lite subordinate (presented upward to `rv32_axi_adapter`) |
| **Output ports** | `uart`, `uart_event`, `uart_byte[7:0]`, `done`, `exit_code[31:0]`, `stat_count/mean_q16/variance_q16` |
| **Architecture** | Two independent `noc_mesh` instances (request path + response path). Four nodes, each with a `noc_endpoint` pair. Node 0: `axi_noc_host` + `welford_stats`. Nodes 1–3: `traffic_client` + `axi_noc_target` + `soc_target`. Traffic control signals routed from node 2's `soc_target`. |
| **Sub-instances** | 2× `noc_mesh`, 8× `noc_endpoint`, 1× `axi_noc_host`, 3× `axi_noc_target`, 3× `traffic_client`, 3× `soc_target`, 1× `welford_stats` |
| **Testbenches** | `tb_axi.sv`, `tb_soc.sv` |

**Node allocation:**

| Node | Coordinates | Peripheral | Address Base |
|------|-------------|-----------|-------------|
| 0 | (0,0) | CPU initiator (`axi_noc_host`) | — |
| 1 | (1,0) | RAM (`soc_target` KIND=1) | `0x0000_0000` |
| 2 | (0,1) | UART + stats (`soc_target` KIND=2) | `0x1000_0000` |
| 3 | (1,1) | Timer + exit (`soc_target` KIND=3) | `0x2000_0000` |

#### `noc_demo_top` — CPU + Adapter + Fabric Top

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_demo_top.sv` |
| **Module** | `noc_demo_top #(FAST=0, MEM_FILE, CLK_HZ, BAUD)` |
| **Description** | Connects `rv32_core` → `rv32_axi_adapter` → `noc_soc_fabric`. Contains a 2-stage reset synchroniser (async assert, sync deassert). Exposes only `clk`, `reset_n`, `uart_tx`, `done`, `trap`, `exit_code`, `uart_event`, `uart_byte`. |
| **Sub-instances** | `rv32_core`, `rv32_axi_adapter`, `noc_soc_fabric` |
| **Testbenches** | `tb/tb_soc.sv` |

#### `noc_board_top` — FPGA Physical Wrapper

| Item | Detail |
|------|--------|
| **File** | `rtl/noc_board_top.sv` |
| **Module** | `noc_board_top #(CLK_HZ, BAUD, FAST)` |
| **Ports** | `clk`, `reset_n` (active-low), `uart_tx` |
| **Description** | Thin wrapper around `noc_demo_top` with `(* keep_hierarchy="yes" *)` attribute for synthesis. Pin assignments come from the board's XDC. Debug outputs (`done`, `trap`, `exit_code`, `uart_byte`) are internally wired but not brought to package pins. |
| **Sub-instances** | `noc_demo_top` |
| **Testbenches** | None (synthesised directly; simulation uses `noc_demo_top` via `tb_soc.sv`) |

---

### 3.11 Minimized Logic

#### `xy_minimized` and `rr_minimized`

| Item | Detail |
|------|--------|
| **File** | `rtl/logic_minimized.sv` |
| **Generator** | `scripts/logic_opt.py` — exhaustively enumerates truth tables and minimizes with ESPRESSO |
| **`xy_minimized`** | Inputs: `{dy[1:0], dx[1:0], YY[1:0], XX[1:0]}` (8 bits). Outputs: `grant[4:0]` (one-hot port). Replaces behavioral XY route for the 2×2 grid. |
| **`rr_minimized`** | Inputs: `{next[2:0], request[4:0]}` (8 bits). Outputs: `grant[4:0]` (one-hot). Replaces behavioral round-robin for N=5. |
| **Comment** | *"Generated by scripts/logic_opt.py; all 256 rows exhaustively checked."* |
| **Instantiated by** | `xy_route` (when `MINIMIZED=1`), `rr_arbiter` (when `MINIMIZED=1` and `N==5`) |

---

## 4. File → Module Mapping (Quick Reference)

| RTL File | Module(s) Defined | Layer |
|---|---|---|
| `rtl/noc_defs.vh` | *(macros only)* | Global |
| `rtl/noc_fifo.sv` | `noc_fifo` | Primitive |
| `rtl/rr_arbiter.sv` | `rr_arbiter` | Primitive |
| `rtl/xy_route.sv` | `xy_route` | Primitive |
| `rtl/logic_minimized.sv` | `xy_minimized`, `rr_minimized` | Primitive (generated) |
| `rtl/noc_router.sv` | `noc_router` | Router |
| `rtl/noc_mesh.sv` | `noc_mesh` | Fabric |
| `rtl/noc_endpoint.sv` | `noc_endpoint` | NI |
| `rtl/axi_noc_host.sv` | `axi_noc_host` | NI |
| `rtl/axi_noc_target.sv` | `axi_noc_target` | NI |
| `rtl/rv32_core.sv` | `rv32_core` | CPU |
| `rtl/rv32_axi_adapter.sv` | `rv32_axi_adapter` | CPU |
| `rtl/unsigned_divider.sv` | `unsigned_divider` | Math |
| `rtl/welford_stats.sv` | `welford_stats` | Stats |
| `rtl/uart_tx.sv` | `uart_tx` | Peripheral |
| `rtl/soc_target.sv` | `soc_target` | Peripheral |
| `rtl/traffic_source.sv` | `traffic_source` | Traffic |
| `rtl/traffic_client.sv` | `traffic_client` | Traffic |
| `rtl/noc_soc_fabric.sv` | `noc_soc_fabric` | Integration |
| `rtl/noc_demo_top.sv` | `noc_demo_top` | Top |
| `rtl/noc_board_top.sv` | `noc_board_top` | Top (FPGA) |

---

## 5. Testbench Coverage Map

| Testbench | File | DUT(s) Instantiated | What It Tests |
|---|---|---|---|
| `tb_core` | `tb/tb_core.sv` | `rv32_core` | Directed RV32I ISA suite (`isa.S`), misaligned LW trap, illegal instruction trap |
| `tb_divider` | `tb/tb_divider.sv` | `unsigned_divider` | File-driven random quotient vectors (`build/divider.in`) |
| `tb_stats` | `tb/tb_stats.sv` | `welford_stats` (→`unsigned_divider`) | File-driven Welford trace; compares RTL output to reference (`build/stats.in` / `stats.out`) |
| `tb_mesh` | `tb/tb_mesh.sv` | `noc_mesh`, `noc_endpoint` (→all router primitives) | Golden trace comparison driven from `+INPUT`/`+OUTPUT` files; supports FAST and MINIMIZED variants |
| `tb_traffic` | `tb/tb_traffic.sv` | `noc_mesh`, `traffic_source`, `noc_endpoint` | Packet integrity (header, sequencing, no duplicates, no loss) at uniform + hotspot rates |
| `tb_deadlock` | `tb/tb_deadlock.sv` | `noc_mesh` (`ALLOW_MIXED=1`), `noc_endpoint` | `MIXED=1`: verifies deadlock state (4 full buffers, 0 credits, cyclic ownership, 100 idle cycles). `MIXED=0`: verifies XY control drains all flits. |
| `tb_axi` | `tb/tb_axi.sv` | `noc_soc_fabric` (→ everything except `rv32_core`) | AXI write/read, byte-enable, misaligned errors, concurrent AW/W, live traffic drain, statistics sanity |
| `tb_soc` | `tb/tb_soc.sv` | `noc_demo_top` (→ full chip) | Software execution (`firmware/main.c`), UART output ≥100 chars, serial pin bit-by-bit decode, exit code 0, latency stats |

### Module → Testbench Cross-Reference

| RTL Module | Primary TB | Also covered by |
|---|---|---|
| `rv32_core` | `tb_core` | `tb_soc` |
| `rv32_axi_adapter` | `tb_soc` | — |
| `unsigned_divider` | `tb_divider` | `tb_stats` |
| `welford_stats` | `tb_stats` | `tb_axi`, `tb_soc` |
| `noc_fifo` | `tb_mesh` | `tb_traffic`, `tb_axi`, `tb_deadlock` |
| `rr_arbiter` | `tb_mesh` | `tb_traffic`, `tb_axi` |
| `xy_route` | `tb_mesh` | `tb_traffic`, `tb_deadlock` |
| `noc_router` | `tb_mesh` | `tb_traffic`, `tb_deadlock`, `tb_axi` |
| `noc_mesh` | `tb_mesh` | `tb_traffic`, `tb_deadlock`, `tb_axi`, `tb_soc` |
| `noc_endpoint` | `tb_mesh` | `tb_traffic`, `tb_deadlock`, `tb_axi`, `tb_soc` |
| `axi_noc_host` | `tb_axi` | `tb_soc` |
| `axi_noc_target` | `tb_axi` | `tb_soc` |
| `traffic_source` | `tb_traffic` | — |
| `traffic_client` | `tb_axi` | `tb_soc` |
| `uart_tx` | `tb_soc` | — |
| `soc_target` | `tb_axi` | `tb_soc` |
| `noc_soc_fabric` | `tb_axi` | `tb_soc` |
| `noc_demo_top` | `tb_soc` | — |
| `noc_board_top` | *(none — FPGA only)* | — |
| `logic_minimized` | `tb_mesh` (MINIMIZED=1) | `tb_traffic` (MINIMIZED=1) |

---

## 6. Formal Verification Harnesses

| File | Harness module | DUT | Properties Proven |
|---|---|---|---|
| `formal/credit_harness.sv` | `credit_harness` | `noc_fifo` | `count ≤ DEPTH`; `credit ≤ DEPTH`; `credit + count == DEPTH` (invariant); no overflow push; no underflow pop |
| `formal/rr_harness.sv` | `rr_harness` | `rr_arbiter` | Grant is one-hot; grant ⊆ request; `grant ≠ 0 ↔ request ≠ 0`; starvation bound: request[0] served within 5 `advance` pulses |
| `formal/check.py` | *(SymbiYosys Python driver)* | Both harnesses | Generates `.sby` job files, runs bounded/k-induction proofs, checks CTL mutual exclusion and fairness properties |

> **Deadlock counterexample:** `noc_router` with `ALLOW_MIXED=1` allows both XY and YX routing per packet. `tb_deadlock` (MIXED=1) demonstrates the resulting deadlock: four buffers fill, all credits drop to zero, ownership forms a cycle, and the network stalls permanently. The XY-only control (`MIXED=0`) is proven deadlock-free by the turn model.

---

## 7. Non-RTL Support Files

### Python Golden Model (`model/`)

| File | Purpose |
|------|---------|
| `model/network.py` | Cycle-accurate mesh simulator: router buffers, XY routing, credit-based flow; used to generate `tb_mesh` stimulus and validate RTL |
| `model/benchmark.py` | Sweeps injection rate (uniform + hotspot), plots latency curves, computes saturation throughput |

### HLS Reference (`hls/`)

| File | Purpose |
|------|---------|
| `hls/welford.cpp` | C++ Welford algorithm — HLS source for `welford_stats.sv` |
| `hls/test_welford.cpp` | C++ testbench for the HLS model |
| `hls/run.tcl` | Vitis HLS project creation and synthesis script |

### Firmware (`firmware/`)

| File | Purpose |
|------|---------|
| `firmware/main.c` | Bare-metal C: writes via UART, reads stats registers, starts/stops traffic, exits via EBREAK |
| `firmware/start.S` | Reset vector; initialises stack pointer and jumps to `main` |
| `firmware/isa.S` | Directed RV32I test sequence; loaded by `tb_core.sv` |
| `firmware/link.ld` | Linker script: code at `0x0000`, data at `0x1000`, stack at top of 16 KB |

### FPGA Flow (`fpga/`)

| File | Purpose |
|------|---------|
| `fpga/build.tcl` | Vivado synthesis + implementation project setup |
| `fpga/xsim.tcl` | Vivado xsim behavioural simulation flow |
| `fpga/program.tcl` | Bitstream download to board |
| `fpga/router_compare.tcl` | Sweeps FAST=0/1, MINIMIZED=0/1; extracts area + Fmax for comparison table |

### Build Scripts (`scripts/`)

| File | Purpose |
|------|---------|
| `scripts/logic_opt.py` | Truth-table exhaustion + ESPRESSO minimization → generates `logic_minimized.sv` |
| `scripts/elaborate.sh` | Verilator/Icarus elaboration for CI lint |
| `scripts/iverilog.sh` / `vvp.sh` | Icarus compile + simulate wrappers |
| `scripts/synth.sh` | Yosys synthesis flow invocation |
| `scripts/bin2hex.py` | Converts ELF/binary to `$readmemh`-compatible hex |
| `scripts/env.sh` / `setup.sh` | Development environment bootstrap |
| `scripts/synth_report.py` / `snapshot_results.py` | Post-synthesis area/timing reporting |

---

*Generated 2026-10-28 · P15 2×2 Mesh NoC with Verified Deadlock Freedom*
