# 2×2 NoC — six-scenario traffic benchmark

This bundle replaces `tb/tb_traffic.sv` with a **single-simulation**, reproducible benchmark, and adds a Python analysis program and notebook. It runs six independently reset scenarios:

| Phase | Generator threshold | Traffic pattern |
|---|---|---|
| 0 | LOW, `16'h2000` | uniform |
| 1 | LOW, `16'h2000` | hotspot |
| 2 | MEDIUM, `16'h8000` | uniform |
| 3 | MEDIUM, `16'h8000` | hotspot |
| 4 | HIGH, `16'hF000` | uniform |
| 5 | HIGH, `16'hF000` | hotspot |

Each scenario uses 2,000 warmup cycles, 10,000 measurement cycles, and then disables new packet generation and drains all accepted packets. The test fails on data corruption, misrouting, duplicate IDs, packet loss, or drain timeout. A reset isolates consecutive scenarios. You can change durations using testbench parameters.

## Vivado usage

1. **Back up your current** `tb/tb_traffic.sv`; copy the new file in its place.
2. Keep the existing `rtl/` sources (including `noc_defs.vh`, `noc_mesh.sv`, `noc_endpoint.sv`, and `traffic_source.sv`) in the Vivado project.
3. Ensure `tb_traffic` is the simulation top. It defaults to `NX=2`, `NY=2`, `FAST=0`.
4. Relaunch **Run Behavioral Simulation** and in the XSIM Tcl console run **`run all`** (or **`run 2000 us`**). Do not use the previous 35-us runtime; the new benchmark has six phases.
5. Confirm six `PHASE PASS` lines followed by `ALL 6 TRAFFIC SCENARIOS PASS`.
6. Find three CSV files in the XSIM working directory, typically `<project>.sim/sim_1/behav/xsim/`:
    - `noc_packet_events.csv`: one row per **completed** packet, with source header-injection cycle, destination tail-delivery cycle, full-packet latency, hop count and traffic scenario.
    - `noc_cycle_stats.csv`: one row per simulated active cycle, with flit transfers, node stalls, outstanding packet count and scenario/window identifiers.
    - `noc_run_summary.csv`: one row per scenario, with integrity and measurement-window totals.

To emit files at custom paths, pass XSIM plusargs such as `+PACKETS=C:/noc/packets.csv +CYCLES=C:/noc/cycles.csv +SUMMARY=C:/noc/summary.csv` (otherwise default filenames are used). Note that paths used by the simulator must be writable.

## Python usage

From the repository root, install dependencies:

```bash
python -m pip install -r analysis/requirements.txt
```

Copy the three CSV files to `analysis/data/` and run:

```bash
python analysis/analyze_noc.py --data-dir analysis/data --output-dir analysis/output
```

The program verifies that the phase totals match the packet log, exports `analysis/output/descriptive_statistics.csv` and `analysis/output/summary_table.md`, then saves **14 charts as both high-resolution PNG and vector PDF** in `analysis/output/figures/`. You can also open `analysis/noc_traffic_analysis.ipynb` to run the graphs individually.

### Baseline vs FAST

The default single simulation provides all **six** traffic cases for **one** hardware configuration. To compare baseline and optimized router implementations, run the same testbench a second time with `FAST=1`, save those three CSV files to a different directory, then:

```bash
python analysis/analyze_noc.py --data-dir analysis/data/baseline --extra-data-dir analysis/data/fast --output-dir analysis/output_comparison
```

It is not valid to claim a baseline-vs-FAST comparison from a single `FAST=0` simulation.

## Important measurement definitions

* **Full-packet latency** = (destination tail-flit accepted cycle) – (source header-flit accepted cycle). The packet contains three flits. This is **not** header-only routing latency.
* **Measurement cohort** = packets whose **first source header handshake** occurs during the 10,000-cycle measurement interval, even when their tail completes in the drain period. Packets beginning during warmup/drain are excluded from latency distributions.
* **Actual accepted injection** = measurement-window packet-header acceptances / (`measurement cycles × number of nodes`). This is the *measured* rate; labels LOW/MEDIUM/HIGH are settings of the generator's Bernoulli threshold only. The generator samples the threshold only when idle and subject to destination rejection.
* **Measured delivery rate** = packets whose tail is accepted **during** measurement / (`measurement cycles × number of nodes`). A boundary offset relative to accepted injection is normal. All phases must eventually deliver all accepted packets.
* **Source stall** = a node-cycle where `tv=1` and `tr=0`; **sink stall** = a node-cycle where `rv=1` and `rr=0`. Neither directly measures internal router buffer occupancy.
* **Hop count** = Manhattan distance in routers. A 2×2 mesh has 1-hop and 2-hop remote routes.
* **Traffic pattern**: uniform destination selection *except self*; hotspot biases traffic toward node 0 for nonzero source nodes. The repository traffic generator gives this biased pattern, not a pure all-to-one workload.
* **No claim of cycle-level golden-model correctness**: this benchmark independently validates packet integrity and collects performance results; a separate independent Python network model must validate per-packet timing for that problem-statement item.
* **No claim of absolute throughput saturation**: sweeping low/medium/high thresholds supplies a first performance curve. Reaching saturation requires confirmed network-limited offered load, potentially a revised injection generator, larger sweeps, and controlled sink readiness.

## GitHub-friendly deliverables

Commit `tb/tb_traffic.sv`, `analysis/analyze_noc.py`, `analysis/noc_traffic_analysis.ipynb`, `analysis/requirements.txt`, selected run CSVs and the resulting figures. Record the Vivado version, git revision and FAST parameter in your report. Avoid committing huge simulation databases or generated `.sim` directories.
