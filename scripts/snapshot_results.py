#!/usr/bin/env python3
"""Archive inspected results after tests; never run or fabricate a benchmark."""
import hashlib
import json
import re
import shutil
from pathlib import Path

out=Path('results'); out.mkdir(exist_ok=True)
for name in ('traffic.csv','mean_latency.svg','mean_queued_latency.svg','delivered_flits_node_cycle.svg'):
    shutil.copyfile(Path('build/benchmark')/name,out/name)
for source,dest in [('build/formal_results.json','formal_results.json'),
                    ('build/logic_results.json','logic_results.json'),
                    ('build/synth/summary.json','router_mapping.json'),
                    ('build/synth/area.svg','area.svg'),
                    ('build/benchmark/summary.json','benchmark_summary.json')]:
    shutil.copyfile(source,out/dest)
uart=Path('build/stats_soc.log').read_text()
blocks=re.findall(r'RV32 2x2 XY CREDIT NOC\n.*?SOC PASS FAST=[01] transactions=\d+',uart,re.S)
assert len(blocks)==2 and all('SYSTEM PASS' in b and 'MEMORY PASS' in b for b in blocks)
(out/'soc_uart.txt').write_text('RTL simulation; UART events were checked against the actual TX serial pin.\n\n'+'\n\n'.join(blocks)+'\n')
axi=Path('build/axi_final.log').read_text()
assert 'AXI PASS FAST=0 transactions=192' in axi and 'AXI PASS FAST=1 transactions=192' in axi
other=Path('build/remaining_final.log').read_text()
stats=Path('build/stats_final.log').read_text()
assert 'DIVIDER PASS vectors=124' in stats and 'HLS saturation/clamp PASS' in stats
assert all(s in other for s in ('RV32I directed ISA PASS checks=25','HARDWARE TRAFFIC PASS NX=2','HARDWARE TRAFFIC PASS NX=3','EXPECTED DEADLOCK','XY DEADLOCK CONTROL PASS'))
model=Path('build/test.log').read_text().split('bash scripts/iverilog.sh -g2012 -Irtl -s tb_axi')[0]
assert model.count('MESH TRACE PASS')==8 and 'Ran 2 tests' in model and '\nOK' in model
assert 'Whole SoC RTL elaboration/check passed' in Path('build/elaborate_run.log').read_text()
record='''Validation on 2026-10-21 (cloud machine, not physical hardware)
Tools: Icarus Verilog 12.0, Yosys 0.52/ABC, RV32 GCC 14.2.0, Python 3.12.

Successful required checks, executed as make test and affected-target reruns:
- model-test: 8 exact RTL/model configurations; 120 variable-length packets each.
- soc-test: baseline and fast; firmware memory/timer/live traffic; serial UART decode.
- axi-test: 192 transactions per variant, independent AW/W, backpressure, reset,
  errors, byte strobes and uniform background traffic; both variants passed.
- core-test: 25 directed ISA result checks, branches/jumps, misalignment/illegal traps.
- stats-test: exact Q16.16 numerical reference, iterative RTL handshake,
  clamp/count/output saturation, C++ count limit, 124 independent divider vectors.
- traffic-test: 524 packets on 2x2 baseline, 1093 on 3x3 fast; no loss/duplicates.
- formal: actual RTL temporal induction, finite CTL abstractions, XY acyclic CDG,
  expected mixed-turn RTL deadlock and passing XY control. Scope: docs/verification.md.
- elaborate: whole SoC synthesis hierarchy/driver checks; no inferred latches.

Additional measurements:
- benchmark: two seeds, uniform/hotspot, 9 rates, both pipelines = 72 runs;
  every run fully drained after measurement and checked packet conservation.
- logic: 256 truth rows for each 5-output block, ESPRESSO/BDD equivalence.
- synth: 3 standalone router variants, generic Xilinx 7-series technology mapping.

Corrections made during development were rerun. The final AXI test waits for
the iterative statistics engine to commit before inspecting its count.
No tests were disabled to produce these passing outcomes.

Unrun/unavailable: Vivado/XSim, Vitis synthesis, board-specific fit/timing/Fmax,
bitstream generation, physical FPGA demo, original VL326 source integration.
No board performance or whole-SoC RTL temporal liveness claim is made.
'''
(out/'validation.txt').write_text(record)
files=[Path('Makefile'),Path('requirements-dev.txt')]
for directory in ('rtl','model','formal','firmware','hls','fpga','scripts','tb','tests'):
    files += [p for p in Path(directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
(out/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Verified result snapshots saved to results/')
