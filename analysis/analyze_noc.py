#!/usr/bin/env python3
"""Reproducible NoC traffic analysis.

Usage:
  python analysis/analyze_noc.py --data-dir <Vivado xsim output directory>
  python analysis/analyze_noc.py --data-dir results/baseline --extra-data-dir results/fast

Input: noc_packet_events.csv, noc_cycle_stats.csv, noc_run_summary.csv.
Output: descriptive_statistics.csv, summary_table.md, figures/*.svg. With no arguments, compare data/Fast=0 and data/Fast=1.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # Works in terminals/CI as well as notebooks.
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator
import numpy as np
import pandas as pd

FILES = {
    "packets": "noc_packet_events.csv",
    "cycles": "noc_cycle_stats.csv",
    "summary": "noc_run_summary.csv",
}
RATE_ORDER = ["low", "medium", "high"]
PATTERN_ORDER = ["uniform", "hotspot"]
CLK_NS = 10


def style() -> None:
    plt.rcParams.update({
        "figure.figsize": (9.5, 5.5),
        "figure.dpi": 130,
        "savefig.dpi": 300,
        "font.size": 10.5,
        "axes.titlesize": 13,
        "axes.labelsize": 11,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.alpha": 0.22,
        "legend.frameon": False,
        "savefig.bbox": "tight",
        "svg.fonttype": "none",
    })


def load_data(data_dir: str | Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    path = Path(data_dir)
    missing = [f for f in FILES.values() if not (path / f).is_file()]
    if missing:
        raise FileNotFoundError(f"In {path}, missing: {missing}")
    packets, cycles, summary = [pd.read_csv(path / f) for f in FILES.values()]
    for df in (packets, cycles, summary):
        df["Pattern"] = df["Pattern"].astype(str).str.lower()
        df["RateLabel"] = df["RateLabel"].astype(str).str.lower()
    validate(packets, cycles, summary, label=str(path))
    return packets, cycles, summary


def validate(pk: pd.DataFrame, cy: pd.DataFrame, sm: pd.DataFrame, label: str = "") -> None:
    required_pk = {"PhaseID", "Pattern", "RateLabel", "RateThreshold", "FAST", "SrcNode", "DestNode", "PacketID", "InjectionCycle", "DeliveryCycle", "LatencyCycles", "HopCount", "InjectionWindow", "DeliveryWindow"}
    required_cy = {"PhaseID", "FAST", "Window", "PhaseCycle", "SourceFlits", "SinkFlits", "SourceStallNodeCycles", "SinkStallNodeCycles", "OutstandingPackets", "StartedPackets", "DeliveredPackets"}
    required_sm = {"PhaseID", "Pattern", "RateLabel", "RateThreshold", "FAST", "NX", "NY", "MeasurementCycles", "MeasuredStartedPackets", "MeasuredInjectedDelivered", "DeliveredPackets", "MeasuredCompletedDuringWindow"}
    for name, df, keys in (("packets", pk, required_pk), ("cycles", cy, required_cy), ("summary", sm, required_sm)):
        if not keys.issubset(df.columns):
            raise ValueError(f"{label} {name} missing {sorted(keys - set(df.columns))}")
        if df.empty:
            raise ValueError(f"{label} {name} file is empty")
    if pk.duplicated(["FAST", "PhaseID", "SrcNode", "PacketID"]).any():
        raise ValueError("Duplicate packet (FAST, phase, source, packet id)")
    if not (pk["LatencyCycles"] == pk["DeliveryCycle"] - pk["InjectionCycle"]).all():
        raise ValueError("LatencyCycles does not match delivery - injection")
    if (pk["LatencyCycles"] <= 0).any():
        raise ValueError("Invalid nonpositive packet latency")
    for _, row in sm.iterrows():
        phase, fast = int(row.PhaseID), int(row.FAST)
        p = pk[(pk.PhaseID == phase) & (pk.FAST == fast)]
        c = cy[(cy.PhaseID == phase) & (cy.FAST == fast)]
        m = p[p.InjectionWindow == 1]
        if len(p) != int(row.DeliveredPackets):
            raise ValueError(f"{label} phase {phase}: packet rows != delivered count")
        if len(m) != int(row.MeasuredStartedPackets) or len(m) != int(row.MeasuredInjectedDelivered):
            raise ValueError(f"{label} phase {phase}: measurement packet accounting failed")
        if (c.Window == 1).sum() != int(row.MeasurementCycles):
            raise ValueError(f"{label} phase {phase}: incorrect measurement window length")
        if (p.DestNode < 0).any() or (p.DestNode >= int(row.NX * row.NY)).any():
            raise ValueError(f"{label} phase {phase}: invalid node index")
    print(f"Validated {label}: {len(sm)} scenarios, {len(pk):,} packets, {len(cy):,} cycles")


def compute_metrics(pk: pd.DataFrame, cy: pd.DataFrame, sm: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, r in sm.iterrows():
        phase, fast = int(r.PhaseID), int(r.FAST)
        p = pk[(pk.PhaseID == phase) & (pk.FAST == fast) & (pk.InjectionWindow == 1)]
        c = cy[(cy.PhaseID == phase) & (cy.FAST == fast) & (cy.Window == 1)]
        duration = int(r.MeasurementCycles)
        n = int(r.NX * r.NY)
        delivered = pk[(pk.PhaseID == phase) & (pk.FAST == fast) & (pk.DeliveryWindow == 1)]
        rows.append({
            "PhaseID": phase,
            "FAST": fast,
            "Pattern": r.Pattern,
            "RateLabel": r.RateLabel,
            "RateThreshold": int(r.RateThreshold),
            "ConfiguredThresholdProbability": float(r.RateThreshold) / 65536.0,
            "WarmupCycles": int(r.WarmupCycles),
            "MeasurementCycles": duration,
            "DrainCycles": int(r.DrainCycles),
            "DeliveredPacketsAllWindows": int(r.DeliveredPackets),
            "MeasuredPackets": len(p),
            "AcceptedInjectionPacketsPerNodePerCycle": len(p) / (duration * n),
            "MeasuredDeliveryPacketsPerNodePerCycle": int(r.MeasuredCompletedDuringWindow) / (duration * n),
            "AcceptedSourceFlitsPerNodePerCycle": c.SourceFlits.sum() / (duration * n),
            "AcceptedSinkFlitsPerNodePerCycle": c.SinkFlits.sum() / (duration * n),
            "MeanLatencyCycles": p.LatencyCycles.mean(),
            "DeliveryWindowMeanLatencyCycles": delivered.LatencyCycles.mean(),
            "MedianLatencyCycles": p.LatencyCycles.median(),
            "P95LatencyCycles": p.LatencyCycles.quantile(0.95),
            "P99LatencyCycles": p.LatencyCycles.quantile(0.99),
            "MaxLatencyCycles": p.LatencyCycles.max(),
            "SourceStallNodeCycleFraction": c.SourceStallNodeCycles.sum() / (duration * n),
            "SinkStallNodeCycleFraction": c.SinkStallNodeCycles.sum() / (duration * n),
            "MeanOutstandingPackets": c.OutstandingPackets.mean(),
        })
    return pd.DataFrame(rows).sort_values(["FAST", "Pattern", "RateThreshold"]).reset_index(drop=True)


def save(fig: plt.Figure, output: Path, name: str) -> None:
    output.mkdir(parents=True, exist_ok=True)
    fig.savefig(output / f"{name}.svg", format="svg", bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"Saved {name}.svg")


def series_label(row: pd.DataFrame) -> str:
    return f"{row.Pattern.iloc[0].capitalize()} · FAST={int(row.FAST.iloc[0])}"


def plot_latency_vs_injection_rate(metrics: pd.DataFrame, out: Path, column: str = "MeanLatencyCycles", name: str = "01_mean_latency_vs_injection_rate") -> None:
    fig, ax = plt.subplots()
    for (_, _), g in metrics.groupby(["FAST", "Pattern"], sort=True):
        g = g.sort_values("AcceptedInjectionPacketsPerNodePerCycle")
        ax.plot(g.AcceptedInjectionPacketsPerNodePerCycle, g[column], marker="o", lw=2, label=series_label(g))
        for _, r in g.iterrows():
            ax.annotate(r.RateLabel[0].upper(), (r.AcceptedInjectionPacketsPerNodePerCycle, r[column]), xytext=(4, 5), textcoords="offset points", fontsize=9)
    ax.set(xlabel="Measured accepted injection (packets / node / cycle)", ylabel=column.replace("LatencyCycles", " latency (cycles)"), title=f"{column.replace('LatencyCycles','')} vs. measured injection rate")
    ax.set_ylim(bottom=0)
    ax.legend()
    fig.tight_layout()
    save(fig, out, name)


def plot_throughput(metrics: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots()
    for (_, _), g in metrics.groupby(["FAST", "Pattern"]):
        g = g.sort_values("ConfiguredThresholdProbability")
        ax.plot(g.ConfiguredThresholdProbability, g.AcceptedInjectionPacketsPerNodePerCycle,
                marker="o", lw=2, label=f"Injected · {series_label(g)}")
        ax.plot(g.ConfiguredThresholdProbability, g.MeasuredDeliveryPacketsPerNodePerCycle,
                marker="s", ls="--", lw=1.6, label=f"Delivered · {series_label(g)}")
    ax.set(xlabel="Configured generator threshold / 65536 (not offered packets/cycle)",
           ylabel="Packets / node / cycle", title="Accepted injection and delivered throughput")
    ax.set_ylim(bottom=0)
    ax.legend(fontsize=9, ncol=2)
    fig.tight_layout()
    save(fig, out, "03_throughput_vs_generator_threshold")


def plot_stalls(metrics: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots()
    for (_, _), g in metrics.groupby(["FAST", "Pattern"]):
        g = g.sort_values("AcceptedInjectionPacketsPerNodePerCycle")
        ax.plot(g.AcceptedInjectionPacketsPerNodePerCycle, 100 * g.SourceStallNodeCycleFraction,
                marker="o", lw=2, label=f"Source backpressure · {series_label(g)}")
        ax.plot(g.AcceptedInjectionPacketsPerNodePerCycle, 100 * g.SinkStallNodeCycleFraction,
                marker="s", ls="--", lw=1.6, label=f"Receiver stall · {series_label(g)}")
    ax.set(xlabel="Accepted injection (packets / node / cycle)",
           ylabel="Fraction of node-cycles stalled (%)", title="Endpoint backpressure vs injection rate")
    ax.set_ylim(bottom=0)
    ax.legend(fontsize=9, ncol=2)
    fig.tight_layout()
    save(fig, out, "04_backpressure_vs_injection_rate")


def plot_latency_box(pk: pd.DataFrame, out: Path) -> None:
    measured = pk[pk.InjectionWindow == 1].copy()
    configs = [(fast, pat, rate) for fast in sorted(measured.FAST.unique()) for pat in PATTERN_ORDER for rate in RATE_ORDER]
    configs = [c for c in configs if not measured[(measured.FAST == c[0]) & (measured.Pattern == c[1]) & (measured.RateLabel == c[2])].empty]
    sets = [measured[(measured.FAST == f) & (measured.Pattern == pat) & (measured.RateLabel == rate)].LatencyCycles.to_numpy() for f, pat, rate in configs]
    labels = [f"{rate[0].upper()} · {pat[:3]}\nFAST={f}" for f, pat, rate in configs]
    fig, ax = plt.subplots(figsize=(max(9, len(sets)*0.95), 5.7))
    ax.boxplot(sets, labels=labels, showfliers=False, showmeans=True)
    ax.set(xlabel="Rate / traffic pattern", ylabel="Header-to-tail latency (cycles)",
           title="Packet latency distribution (box = IQR, whiskers = 1.5 IQR)")
    ax.set_ylim(bottom=0)
    fig.tight_layout()
    save(fig, out, "05_latency_distribution_boxplots")


def plot_high_rate_ecdf(pk: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots()
    subset = pk[(pk.InjectionWindow == 1) & (pk.RateLabel == "high")]
    for (_, _), g in subset.groupby(["FAST", "Pattern"]):
        v = np.sort(g.LatencyCycles.to_numpy())
        y = np.arange(1, len(v)+1) / len(v)
        ax.step(v, y, where="post", lw=2, label=series_label(g))
    ax.set(xlabel="Header-to-tail packet latency (cycles)", ylabel="Fraction of packets ≤ latency",
           title="High-injection packet latency CDF")
    ax.set_ylim(0, 1.03)
    ax.legend()
    fig.tight_layout()
    save(fig, out, "06_high_rate_latency_ecdf")


def choose_high_hotspot(cy: pd.DataFrame) -> pd.DataFrame:
    fast = int(min(cy.FAST.unique()))
    return cy[(cy.FAST == fast) & (cy.Pattern == "hotspot") & (cy.RateLabel == "high")].sort_values("PhaseCycle").copy()


def plot_flit_activity(cy: pd.DataFrame, out: Path, window: int = 100) -> None:
    g = choose_high_hotspot(cy)
    g = g[g.Window == 1].copy()
    for col in ["SourceFlits", "SinkFlits"]:
        g[col + "Avg"] = g[col].rolling(window, min_periods=1).mean()
    fig, ax = plt.subplots()
    ax.plot(g.PhaseCycle * CLK_NS / 1000, g.SourceFlitsAvg, label="Accepted source flits/cycle", lw=1.7)
    ax.plot(g.PhaseCycle * CLK_NS / 1000, g.SinkFlitsAvg, label="Accepted sink flits/cycle", lw=1.7)
    ax.set(xlabel="Time since phase reset (µs)", ylabel="Flits per cycle (rolling average)",
           title=f"High-hotspot flit activity — FAST={int(g.FAST.iloc[0])}")
    ax.legend()
    fig.tight_layout()
    save(fig, out, "07_high_hotspot_flit_activity")


def plot_outstanding(cy: pd.DataFrame, out: Path) -> None:
    g = choose_high_hotspot(cy)
    fig, ax = plt.subplots()
    ax.plot(g.PhaseCycle * CLK_NS / 1000, g.OutstandingPackets, lw=1.4)
    start_measure = g.loc[g.Window == 1, "PhaseCycle"].min() * CLK_NS / 1000
    end_measure = g.loc[g.Window == 1, "PhaseCycle"].max() * CLK_NS / 1000
    ax.axvspan(start_measure, end_measure, alpha=0.09, label="Measurement window")
    ax.set(xlabel="Time since phase reset (µs)", ylabel="Headers accepted but packets not yet delivered",
           title="In-flight / buffered packets — high hotspot")
    ax.set_ylim(bottom=0)
    ax.legend()
    fig.tight_layout()
    save(fig, out, "08_high_hotspot_outstanding_packets")


def plot_matrix(pk: pd.DataFrame, out: Path, pattern: str) -> None:
    fast = int(min(pk.FAST.unique()))
    g = pk[(pk.FAST == fast) & (pk.RateLabel == "high") & (pk.Pattern == pattern) & (pk.InjectionWindow == 1)]
    if g.empty:
        return
    n = max(int(pk.SrcNode.max()), int(pk.DestNode.max())) + 1
    m = pd.crosstab(g.SrcNode, g.DestNode).reindex(index=range(n), columns=range(n), fill_value=0)
    fig, ax = plt.subplots(figsize=(7.2, 6))
    im = ax.imshow(m.to_numpy(), cmap="Blues")
    ax.grid(False)
    ax.set(xticks=list(range(n)), yticks=list(range(n)),
           xticklabels=[f"R{i}" for i in range(n)], yticklabels=[f"R{i}" for i in range(n)],
           xlabel="Destination", ylabel="Source",
           title=f"High-rate {pattern} source–destination matrix")
    threshold = m.to_numpy().max() / 2
    for i in range(n):
        for j in range(n):
            ax.text(j, i, str(m.iloc[i, j]), va="center", ha="center",
                    color="white" if m.iloc[i, j] > threshold else "black")
    fig.colorbar(im, ax=ax, label="Completed measurement-injected packets")
    fig.tight_layout()
    save(fig, out, f"09_traffic_matrix_high_{pattern}")


def plot_source_fairness(pk: pd.DataFrame, out: Path) -> None:
    g = pk[(pk.RateLabel == "high") & (pk.InjectionWindow == 1)].copy()
    if g.empty:
        return
    n = int(max(g.SrcNode.max(), g.DestNode.max()))+1
    fig, ax = plt.subplots()
    table = g.groupby(["FAST", "Pattern", "SrcNode"]).size().unstack([0, 1], fill_value=0).reindex(range(n), fill_value=0)
    table.plot(kind="bar", ax=ax, width=0.8)
    ax.set(xlabel="Source node", ylabel="Delivered packets from measurement window",
           title="Source service distribution — high injection")
    ax.set_xticklabels([f"R{i}" for i in range(n)], rotation=0)
    ax.legend(title="FAST / pattern", fontsize=9)
    fig.tight_layout()
    save(fig, out, "10_high_rate_deliveries_by_source")


def plot_hop_latency(pk: pd.DataFrame, out: Path) -> None:
    g = pk[pk.InjectionWindow == 1].copy()
    fig, ax = plt.subplots()
    for (_, _), group in g.groupby(["FAST", "Pattern"]):
        means = group.groupby("HopCount").LatencyCycles.mean().sort_index()
        ax.plot(means.index, means.values, marker="o", lw=2, label=series_label(group))
    ax.set(xlabel="Manhattan distance (router hops)", ylabel="Mean packet latency (cycles)",
           title="Latency vs route distance (all measured rates)")
    ax.xaxis.set_major_locator(MaxNLocator(integer=True))
    ax.set_ylim(bottom=0)
    ax.legend()
    fig.tight_layout()
    save(fig, out, "11_latency_vs_hop_count")


def plot_packet_progress(cy: pd.DataFrame, out: Path) -> None:
    g = choose_high_hotspot(cy)
    fig, ax = plt.subplots()
    ax.step(g.PhaseCycle * CLK_NS/1000, g.StartedPackets, where="post", label="Packet headers accepted", lw=1.8)
    ax.step(g.PhaseCycle * CLK_NS/1000, g.DeliveredPackets, where="post", label="Complete packets delivered", lw=1.8)
    ax.set(xlabel="Time since phase reset (µs)", ylabel="Cumulative packet count",
           title="High-hotspot packet injection/delivery progress")
    ax.legend()
    fig.tight_layout()
    save(fig, out, "12_high_hotspot_packet_progress")


def plot_grouped_rate_latency(metrics: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots()
    for (_, _), g in metrics.groupby(["FAST", "Pattern"]):
        g = g.sort_values("ConfiguredThresholdProbability")
        ax.plot(g.ConfiguredThresholdProbability, g.MeanLatencyCycles, marker="o", lw=2, label=series_label(g))
    ax.set(xlabel="Configured generator threshold / 65536", ylabel="Mean full-packet latency (cycles)",
           title="Latency vs configured traffic-generator threshold")
    ax.set_ylim(bottom=0)
    ax.legend()
    fig.tight_layout()
    save(fig, out, "13_latency_vs_generator_threshold")


def load_runs(data_dirs) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Load disjoint hardware runs without silently counting a phase twice."""
    sets = [load_data(path) for path in data_dirs]
    pk, cy, sm = [pd.concat(parts, ignore_index=True) for parts in zip(*sets)]
    if sm.duplicated(["FAST", "PhaseID"]).any():
        raise ValueError("Input data sets must have unique (FAST, PhaseID) combinations")
    return pk, cy, sm


def plot_model_comparison(metrics: pd.DataFrame, out: Path) -> None:
    """Golden-model panel layout using observable RTL quantities.

    Delivery-window latency matches the model's cohort convention. RTL logs
    cannot recover generation-to-tail latency or offered flits/node/cycle.
    """
    for column, name, ylabel in (
        ("DeliveryWindowMeanLatencyCycles", "mean_latency", "Accepted header to tail latency (cycles)"),
        ("AcceptedSinkFlitsPerNodePerCycle", "delivered_flits_node_cycle", "Delivered flits / node / cycle"),
    ):
        fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), layout="constrained")
        for ax, pattern in zip(axes, PATTERN_ORDER):
            for fast, group in metrics[metrics.Pattern == pattern].groupby("FAST"):
                group = group.sort_values("ConfiguredThresholdProbability")
                ax.plot(group.ConfiguredThresholdProbability, group[column], "o-",
                        label=f"{'fast' if fast else 'baseline'} (FAST={int(fast)})")
            ax.set(title=pattern.capitalize(), xlabel="Generator threshold / 65536", ylabel=ylabel)
            ax.set_ylim(bottom=0)
            ax.legend()
        save(fig, out, name)


def plot_all(pk: pd.DataFrame, cy: pd.DataFrame, metrics: pd.DataFrame, out: Path) -> None:
    style()
    plot_latency_vs_injection_rate(metrics, out)
    plot_latency_vs_injection_rate(metrics, out, "P95LatencyCycles", "02_p95_latency_vs_injection_rate")
    plot_throughput(metrics, out)
    plot_stalls(metrics, out)
    plot_latency_box(pk, out)
    plot_high_rate_ecdf(pk, out)
    for fast in sorted(pk.FAST.unique()):
        variant_out = out / f"FAST={int(fast)}"
        variant_cycles = cy[cy.FAST == fast]
        variant_packets = pk[pk.FAST == fast]
        plot_flit_activity(variant_cycles, variant_out)
        plot_outstanding(variant_cycles, variant_out)
        plot_matrix(variant_packets, variant_out, "uniform")
        plot_matrix(variant_packets, variant_out, "hotspot")
        plot_packet_progress(variant_cycles, variant_out)
    plot_source_fairness(pk, out)
    plot_hop_latency(pk, out)
    plot_grouped_rate_latency(metrics, out)
    plot_model_comparison(metrics, out)


def write_summary(metrics: pd.DataFrame, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output / "descriptive_statistics.csv", index=False, float_format="%.7f")
    keep = ["FAST", "Pattern", "RateLabel", "MeasuredPackets",
            "AcceptedInjectionPacketsPerNodePerCycle", "MeanLatencyCycles",
            "P95LatencyCycles", "MeasuredDeliveryPacketsPerNodePerCycle",
            "SourceStallNodeCycleFraction", "SinkStallNodeCycleFraction"]
    report = metrics[keep].copy().round(5)
    try:
        table = report.to_markdown(index=False)
    except ImportError:
        table = report.to_string(index=False)
    (output / "summary_table.md").write_text(
        "# 2×2 NoC traffic benchmark\n\n"
        "Latency = source-accepted header to destination-accepted tail. "
        "Measurement packets are selected by their header injection window; "
        "they remain included when delivered during drain. "
        "Configured threshold is **not** offered packets/node/cycle.\n\n" + table + "\n",
        encoding="utf-8")
    print("\n" + table + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=None, help="Single run folder; defaults to comparing data/Fast=0 and data/Fast=1")
    parser.add_argument("--extra-data-dir", type=Path, default=None, help="Optional second run (e.g. FAST=1)")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "output")
    args = parser.parse_args()
    if args.extra_data_dir and args.data_dir is None:
        parser.error("--extra-data-dir requires --data-dir")
    data_dirs = ([args.data_dir] + ([args.extra_data_dir] if args.extra_data_dir else [])
                 if args.data_dir else [Path(__file__).resolve().parent / "data" / f"Fast={fast}" for fast in (0, 1)])
    pk, cy, sm = load_runs(data_dirs)
    metrics = compute_metrics(pk, cy, sm)
    write_summary(metrics, args.output_dir)
    plot_all(pk, cy, metrics, args.output_dir / "figures")
    print("\nAnalysis complete:", args.output_dir.resolve())


if __name__ == "__main__":
    main()
