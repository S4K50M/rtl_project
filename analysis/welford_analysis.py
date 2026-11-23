#!/usr/bin/env python3
"""Offline Welford verification on baseline NoC packet latencies.

Defaults resolve from this file, so invocation works from any directory.
This validates the algorithms, not RTL simulation or ready/valid timing.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCALE = 1 << 16
MAX_Q16 = (1 << 32) - 1


def analyze_samples(samples, max_samples=65535):
    """Check every prefix and emulate committed welford_stats Q16.16 outputs.

    The independent reference uses integer sums and squared sums, avoiding
    cancellation in the population-variance numerator. All references use the
    same accepted, clamped samples as the hardware algorithm.
    """
    if not 1 <= max_samples <= 65535:
        raise ValueError('max_samples must be in 1..65535')
    n = total = squares = mean_q16 = m2_q16 = 0
    mean = m2 = 0.0
    trace = []
    for index, raw in enumerate(samples, 1):
        if not isinstance(raw, int) or not 0 <= raw <= 0xffffffff:
            raise ValueError(f'Sample {index}: expected an unsigned 32-bit integer')
        accepted = n < max_samples
        x = min(raw, 32767)
        if accepted:
            n += 1
            total += x
            squares += x*x
            delta = x - mean
            mean += delta/n
            m2 += delta*(x-mean)
            delta_q16 = (x << 16) - mean_q16
            # Signed division in RTL/HLS truncates toward zero, not -infinity.
            mean_q16 += (1 if delta_q16 >= 0 else -1)*(abs(delta_q16)//n)
            m2_q16 += (delta_q16*((x << 16)-mean_q16)) >> 16
        ref_mean = total/n
        ref_variance = (n*squares-total*total)/(n*n)
        variance = m2/n
        if not (math.isclose(mean, ref_mean, rel_tol=1e-10, abs_tol=1e-9)
                and math.isclose(variance, ref_variance, rel_tol=1e-10, abs_tol=1e-8)):
            raise AssertionError(f'Floating Welford mismatch at sample {index}')
        variance_q16 = min(MAX_Q16, m2_q16//n)
        trace.append(dict(sample_index=index, latency_cycles=raw,
                          clamped_latency_cycles=x, accepted=int(accepted), count=n,
                          reference_mean=ref_mean, reference_population_variance=ref_variance,
                          welford_mean=mean, welford_population_variance=variance,
                          mean_q16=mean_q16, variance_q16=variance_q16,
                          fixed_mean=mean_q16/SCALE, fixed_population_variance=variance_q16/SCALE,
                          fixed_mean_error=mean_q16/SCALE-ref_mean,
                          fixed_variance_error=variance_q16/SCALE-ref_variance,
                          variance_saturated=int(m2_q16//n > MAX_Q16)))
    if not trace:
        raise ValueError('No latency samples selected')
    last = trace[-1]
    summary = dict(input_samples=len(trace), accepted_samples=n,
                   ignored_after_count_limit=len(trace)-n,
                   clamped_accepted_samples=sum(r['accepted'] and r['latency_cycles']>32767 for r in trace),
                   floating_prefix_checks_passed=True,
                   reference_mean=last['reference_mean'],
                   reference_population_variance=last['reference_population_variance'],
                   mean_q16=last['mean_q16'], variance_q16=last['variance_q16'],
                   fixed_mean=last['fixed_mean'],
                   fixed_population_variance=last['fixed_population_variance'],
                   final_fixed_mean_error=last['fixed_mean_error'],
                   final_fixed_variance_error=last['fixed_variance_error'],
                   max_abs_fixed_mean_error=max(abs(r['fixed_mean_error']) for r in trace),
                   max_abs_fixed_variance_error=max(abs(r['fixed_variance_error']) for r in trace),
                   saturated_variance_prefixes=sum(r['variance_saturated'] for r in trace))
    return trace, summary


def load_scenarios(path, cohort):
    with path.open(newline='', encoding='utf-8-sig') as handle:
        reader = csv.DictReader(handle)
        required = {'FAST', 'PhaseID', 'Pattern', 'RateLabel', 'SrcNode', 'PacketID',
                    'InjectionCycle', 'DeliveryCycle', 'LatencyCycles', 'InjectionWindow'}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f'Missing packet columns: {sorted(required-set(reader.fieldnames or []))}')
        groups, seen = {}, set()
        for line, row in enumerate(reader, 2):
            if int(row['FAST']) != 0:
                raise ValueError(f'Line {line}: expected baseline FAST=0 data')
            identity = tuple(int(row[k]) for k in ('PhaseID', 'SrcNode', 'PacketID'))
            if identity in seen:
                raise ValueError(f'Line {line}: duplicate packet {identity}')
            seen.add(identity)
            latency = int(row['LatencyCycles'])
            if latency <= 0 or latency != int(row['DeliveryCycle'])-int(row['InjectionCycle']):
                raise ValueError(f'Line {line}: inconsistent latency')
            if cohort == 'measurement' and int(row['InjectionWindow']) != 1:
                continue
            pattern, rate = row['Pattern'].lower(), row['RateLabel'].lower()
            if pattern not in ('uniform', 'hotspot') or rate not in ('low', 'medium', 'high'):
                raise ValueError(f'Line {line}: unsupported traffic scenario')
            key = (int(row['PhaseID']), pattern, rate)
            groups.setdefault(key, []).append(row)
    if not groups:
        raise ValueError('No baseline packets found for selected cohort')
    # Delivery order models a completed-packet stream; source/id break same-cycle ties.
    for rows in groups.values():
        rows.sort(key=lambda r: tuple(int(r[k]) for k in ('DeliveryCycle', 'SrcNode', 'PacketID')))
    return groups


def write_csv(path, rows):
    with path.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def plot_traces(traces, output):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    for pattern in ('uniform', 'hotspot'):
        selected = [(key, rows) for key, rows in traces.items() if key[1] == pattern]
        if not selected:
            continue
        fig, axes = plt.subplots(2, 2, figsize=(12, 8), layout='constrained')
        for (_, _, rate), rows in selected:
            count = [r['sample_index'] for r in rows]
            for ax, column in zip(axes.flat, ('welford_mean', 'welford_population_variance',
                                             'fixed_mean_error', 'fixed_variance_error')):
                ax.plot(count, [r[column] for r in rows], label=rate)
        for ax, title in zip(axes.flat, ('Floating Welford mean (cycles)',
                                        'Floating population variance (cycles squared)',
                                        'Q16.16 mean error (cycles)',
                                        'Q16.16 variance error (cycles squared)')):
            ax.set(title=title, xlabel='Completed packet sample index')
            ax.grid(alpha=.25)
            ax.legend()
        fig.suptitle(f'Baseline FAST=0: {pattern}')
        fig.savefig(output / f'welford_{pattern}.svg', format='svg')
        plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=ROOT/'analysis/data/Espresso=0/Fast=0')
    parser.add_argument('--output-dir', type=Path, default=ROOT/'analysis/output/welford_baseline')
    parser.add_argument('--cohort', choices=('measurement', 'all'), default='measurement',
                        help='Default: measurement-injected packets, including drain deliveries')
    parser.add_argument('--max-samples', type=int, default=65535,
                        help='Per-scenario hardware count limit (default: 65535)')
    parser.add_argument('--no-plots', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.max_samples <= 65535:
        parser.error('--max-samples must be in 1..65535')
    groups = load_scenarios(args.data_dir/'noc_packet_events.csv', args.cohort)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    summaries, traces = [], {}
    for key, packets in sorted(groups.items()):
        phase, pattern, rate = key
        trace, summary = analyze_samples([int(r['LatencyCycles']) for r in packets], args.max_samples)
        # Retain packet identity so each numerical prefix is reproducible.
        for step, packet in zip(trace, packets):
            step.update(source_node=int(packet['SrcNode']), packet_id=int(packet['PacketID']),
                        delivery_cycle=int(packet['DeliveryCycle']))
        write_csv(args.output_dir/f'phase_{phase}_{pattern}_{rate}_trace.csv', trace)
        summaries.append(dict(FAST=0, PhaseID=phase, Pattern=pattern, RateLabel=rate, **summary))
        traces[key] = trace
        print(f'{pattern}/{rate}: {summary["accepted_samples"]} samples, prefix checks PASS')
    write_csv(args.output_dir/'welford_summary.csv', summaries)
    report = dict(method='Offline floating Welford vs integer-sum reference; Q16.16 RTL algorithm emulation',
                  rtl_simulated=False, cohort=args.cohort, population_variance=True,
                  source=str((args.data_dir/'noc_packet_events.csv').resolve()),
                  order='DeliveryCycle, SrcNode, PacketID; independent reset for each phase',
                  max_samples=args.max_samples, scenarios=summaries)
    (args.output_dir/'welford_report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    if not args.no_plots:
        plot_traces(traces, args.output_dir)
    print(f'Outputs: {args.output_dir.resolve()}')


if __name__ == '__main__':
    main()
