#!/usr/bin/env python3
"""Generate synthesizable SOP blocks with PyEDA ESPRESSO, check with ROBDDs.
Run from any directory using the path to this script.
Outputs: rtl/logic_minimized.sv, build/espresso_bdd_report.json
Default outputs are relative to the repository, not the working directory.
Explicit --rtl and --report paths are relative to the working directory.
"""
import argparse
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

try:
    from pyeda.inter import exprvars, truthtable, espresso_tts, expr2bdd
except ImportError as exc:
    raise SystemExit("Install PyEDA first: python -m pip install pyeda") from exc


def xy_spec(n):
    x, y, dx, dy = n & 3, (n >> 2) & 3, (n >> 4) & 3, (n >> 6) & 3
    port = 1 if dx > x else 2 if dx < x else 3 if dy > y else 4 if dy < y else 0
    return 1 << port


def rr_spec(n):
    req, priority = n & 31, (n >> 5) & 7
    if priority > 4:
        return 0  # unreachable from normal reset/update; defined for all 256 rows
    for j in range(5):
        p = (priority + j) % 5
        if (req >> p) & 1:
            return 1 << p
    return 0


def emit_ast(ast, bit_index):
    op, *args = ast
    if op == 'const':
        return "1'b1" if args[0] else "1'b0"
    if op == 'lit':
        a = args[0]
        return ('~' if a < 0 else '') + f'v[{bit_index[abs(a)]}]'
    if op in ('and', 'or'):
        sym = ' & ' if op == 'and' else ' | '
        return '(' + sym.join(emit_ast(a, bit_index) for a in args) + ')'
    raise ValueError(f'Unexpected AST: {ast}')


def generate(name, reference):
    variables = exprvars('v', 8)
    truth_tables = [truthtable(variables, ''.join(str((reference(i) >> b) & 1)
                                              for i in range(256))) for b in range(5)]
    espresso = espresso_tts(*truth_tables)
    bdds = [expr2bdd(expression) for expression in espresso]
    for i in range(256):
        assignment = {variables[b]: (i >> b) & 1 for b in range(8)}
        sop_output = sum(int(expr.restrict(assignment).is_one()) << b
                         for b, expr in enumerate(espresso))
        expected = reference(i)
        if sop_output != expected:
            raise AssertionError((name, 'ESPRESSO mismatch', i, sop_output, expected))
        for b, bdd in enumerate(bdds):
            bdd_assignment = {var: (i >> int(var.indices[0])) & 1 for var in bdd.inputs}
            bdd_bit = int(bdd.restrict(bdd_assignment).is_one())
            if bdd_bit != ((expected >> b) & 1):
                raise AssertionError((name, 'BDD mismatch', i, b, bdd_bit))
    index = {v.uniqid: i for i, v in enumerate(variables)}
    result = [f'module {name}(input wire [7:0] v, output wire [4:0] grant);']
    for b, e in enumerate(espresso):
        result.append(f'    assign grant[{b}] = {emit_ast(e.to_ast(), index)};')
    result.append('endmodule')
    report = dict(truth_table_rows=256, output_bits=5, exhaustive_equivalence=True,
                  espresso_product_terms=sum(len(e.cover) for e in espresso),
                  bdd_nodes_per_output=[len(list(b.dfs_postorder())) for b in bdds])
    return '\n'.join(result), report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rtl', type=Path, default=REPO_ROOT / 'rtl' / 'logic_minimized.sv',
                        help='RTL output path (default: repository rtl/logic_minimized.sv)')
    parser.add_argument('--report', type=Path, default=REPO_ROOT / 'build' / 'espresso_bdd_report.json',
                        help='JSON report path (default: repository build/espresso_bdd_report.json)')
    args = parser.parse_args()
    route_rtl, route_report = generate('xy_minimized', xy_spec)
    rr_rtl, rr_report = generate('rr_minimized', rr_spec)
    rtl = args.rtl.resolve()
    report = args.report.resolve()
    rtl.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    rtl.write_text('// Generated and verified by scripts/logic_opt_espresso.py\n'
                   + route_rtl + '\n\n' + rr_rtl + '\n', encoding='utf-8')
    results = {'xy_route': route_report, 'round_robin': rr_report,
               'note': 'Truth-table and BDD correctness; does not establish smaller FPGA area.'}
    report.write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(results, indent=2))
    print('ESPRESSO + ROBDD 256/256 each: PASS')
    print(f'RTL: {rtl}')
    print(f'Report: {report}')

if __name__ == '__main__':
    main()
