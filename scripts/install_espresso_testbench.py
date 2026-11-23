#!/usr/bin/env python3
"""Add an optional MINIMIZED testbench parameter without altering default behaviour.
Run from any directory using the path to this script.
Paths are relative to the repository. Idempotent; keeps tb/tb_traffic.sv.bak.
"""
from pathlib import Path
REPO_ROOT = Path(__file__).resolve().parent.parent
p = REPO_ROOT / 'tb' / 'tb_traffic.sv'
if not p.exists():
    raise SystemExit(f'Testbench missing: {p}')
src = p.read_text(encoding='utf-8')
if 'parameter MINIMIZED = 0;' in src:
    print('MINIMIZED already installed; no changes')
else:
    old = '    parameter NX = 2, NY = 2, FAST = 0;'
    new = old + '\n    parameter MINIMIZED = 0;'
    if src.count(old) != 1:
        raise SystemExit('Unexpected tb_traffic.sv parameter structure; edit manually')
    src = src.replace(old, new)
    old_mesh = 'noc_mesh #(.NX(NX), .NY(NY), .FAST(FAST)) mesh ('
    new_mesh = 'noc_mesh #(.NX(NX), .NY(NY), .FAST(FAST), .MINIMIZED(MINIMIZED)) mesh ('
    if src.count(old_mesh) != 1:
        raise SystemExit('Unexpected noc_mesh instantiation; edit manually')
    src = src.replace(old_mesh, new_mesh)
    p.with_suffix('.sv.bak').write_text(p.read_text(encoding='utf-8'), encoding='utf-8')
    p.write_text(src, encoding='utf-8')
    print(f'Installed optional tb_traffic.MINIMIZED=0 in {p}')
    print(f'Original saved as {p.with_suffix(".sv.bak")}')
