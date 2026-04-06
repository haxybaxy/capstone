#!/usr/bin/env python3
"""Generate publication figures for N-body capstone paper.

Reads CSV data from ../galaxysim/results/ and browser logs from
../galaxysim/web_results.txt.  Outputs PNGs to figures/.
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import re
import os
from datetime import datetime

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "galaxysim", "results")
WEB_RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "galaxysim", "web_results.txt")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")

WARMUP = 10  # skip first 10 steps for timing measurements

# ── Academic plot style ─────────────────────────────────────────────
plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["CMU Serif", "DejaVu Serif", "Times New Roman", "Times"],
    "font.size": 11,
    "axes.labelsize": 12,
    "axes.titlesize": 13,
    "legend.fontsize": 10,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
    "savefig.facecolor": "white",
    "savefig.dpi": 300,
    "figure.dpi": 150,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "grid.linestyle": "--",
})


# ── Helpers ─────────────────────────────────────────────────────────

def load_csv(name):
    """Load a results CSV, skipping warmup rows."""
    return pd.read_csv(os.path.join(RESULTS, name)).iloc[WARMUP:]


def mean_total_ms(df):
    """Mean total ms/step from the three timing columns."""
    return (df["tree_build_ms"] + df["force_ms"] + df["integrate_ms"]).mean()


def parse_web_results(path):
    """Parse web_results.txt -> {N: wall-clock ms/step} via timestamps.

    The logged GPU kernel times are sub-millisecond, but actual wall-clock
    time per step includes browser/JS overhead.  We compute it from the
    timestamp difference between Step 100 and Step 1000 (900 steps).
    """
    with open(path) as f:
        text = f.read()

    blocks = re.split(r"\n\s*\n", text.strip())
    results = {}

    for block in blocks:
        init = re.search(r"Simulation initialized: (\d+) particles", block)
        if not init:
            continue
        n = int(init.group(1))

        step_times = {}
        for line in block.split("\n"):
            m = re.search(
                r"\[?(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\].*Step (\d+)/",
                line,
            )
            if m:
                ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")
                step_times[int(m.group(2))] = ts

        if 100 in step_times and 1000 in step_times:
            dt_s = (step_times[1000] - step_times[100]).total_seconds()
            results[n] = (dt_s / 900) * 1000  # ms per step

    return results


# ── Fig 1: N-scaling (log-log) ──────────────────────────────────────

def fig1_n_scaling():
    ns = [100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000]
    times = [mean_total_ms(load_csv(f"B_scale_N{n}.csv")) for n in ns]

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.loglog(ns, times, "o-", color="#2563eb", ms=6, lw=2, label="Measured")

    # O(N log N) reference line, scaled to pass through the midpoint
    ref = np.array(ns, dtype=float)
    nlogn = ref * np.log2(ref)
    mid = len(ns) // 2
    scale = times[mid] / nlogn[mid]
    ax.loglog(ref, nlogn * scale, "--", color="gray", alpha=0.6,
              label=r"$O(N \log N)$ reference")

    ax.set_xlabel("Number of Particles ($N$)")
    ax.set_ylabel("Mean ms / step")
    ax.set_title("Barnes\u2013Hut Tree Scaling (Plummer Sphere)")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig_n_scaling_plummer.png"))
    plt.close(fig)
    print(f"  Fig 1: N-scaling \u2014 {times[0]:.2f} ms (N=100) \u2192 {times[-1]:.2f} ms (N=100K)")


# ── Fig 2: Direct vs Tree crossover (log-log) ──────────────────────

def fig2_crossover():
    ns = [100, 200, 500, 1000, 2000, 5000]
    direct = [mean_total_ms(load_csv(f"D_direct_N{n}.csv")) for n in ns]
    tree = [mean_total_ms(load_csv(f"D_tree_N{n}.csv")) for n in ns]

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.loglog(ns, direct, "s-", color="#ea580c", ms=6, lw=2,
              label=r"Direct $O(N^2)$")
    ax.loglog(ns, tree, "o-", color="#2563eb", ms=6, lw=2,
              label=r"Tree $O(N \log N)$")

    ax.set_xlabel("Number of Particles ($N$)")
    ax.set_ylabel("Mean ms / step")
    ax.set_title("Direct vs. Tree Force Computation")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig_crossover.png"))
    plt.close(fig)
    print(f"  Fig 2: Crossover \u2014 direct {direct[0]:.2f}\u2192{direct[-1]:.2f}, "
          f"tree {tree[0]:.2f}\u2192{tree[-1]:.2f}")


# ── Fig 3: Timing decomposition (stacked bar) ──────────────────────

def fig3_timing_decomp():
    ns = [1000, 5000, 10000, 50000, 100000]
    tree_b, force, integ = [], [], []
    for n in ns:
        df = load_csv(f"B_scale_N{n}.csv")
        tree_b.append(df["tree_build_ms"].mean())
        force.append(df["force_ms"].mean())
        integ.append(df["integrate_ms"].mean())

    tree_b = np.array(tree_b)
    force = np.array(force)
    integ = np.array(integ)
    x = np.arange(len(ns))
    w = 0.55

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.bar(x, tree_b, w, label="Tree Build", color="#2563eb")
    ax.bar(x, force, w, bottom=tree_b, label="Force Eval", color="#ea580c")
    ax.bar(x, integ, w, bottom=tree_b + force, label="Integration", color="#16a34a")

    ax.set_xticks(x)
    ax.set_xticklabels([f"{n:,}" for n in ns])
    ax.set_xlabel("Number of Particles ($N$)")
    ax.set_ylabel("Mean ms / step")
    ax.set_title("Timing Decomposition by Phase")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig_timing_decomp.png"))
    plt.close(fig)
    totals = tree_b + force + integ
    print(f"  Fig 3: Timing decomp \u2014 totals {totals[0]:.2f}\u2192{totals[-1]:.2f} ms")


# ── Fig 4: Energy drift (dual line) ────────────────────────────────

def fig4_energy_drift():
    df_lf = pd.read_csv(os.path.join(RESULTS, "B_scale_N5000.csv"))
    df_eu = pd.read_csv(os.path.join(RESULTS, "B_euler_dt001.csv"))

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot(df_lf["step"], df_lf["energy_drift"],
            color="#2563eb", lw=1.5, label="Leapfrog (KDK)")
    ax.plot(df_eu["step"], df_eu["energy_drift"],
            "--", color="#ea580c", lw=1.5, label="Euler")

    ax.set_xlabel("Step")
    ax.set_ylabel(r"Relative Energy Drift $|\Delta E / E_0|$")
    ax.set_title("Energy Conservation: Leapfrog vs. Euler ($N = 5{,}000$)")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig_energy_drift.png"))
    plt.close(fig)
    print(f"  Fig 4: Energy drift \u2014 LF final={df_lf['energy_drift'].iloc[-1]:.4f}, "
          f"Euler final={df_eu['energy_drift'].iloc[-1]:.6f}")


# ── Fig 5: Native vs Browser (log-x, linear-y) ────────────────────

def fig5_web_native():
    ns = [100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000]
    native = [mean_total_ms(load_csv(f"B_scale_N{n}.csv")) for n in ns]

    web = parse_web_results(WEB_RESULTS)
    web_ns = sorted(web.keys())
    web_t = [web[n] for n in web_ns]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(ns, native, "o-", color="#2563eb", ms=5, lw=2,
            label="Native (C++/Dawn)")
    ax.plot(web_ns, web_t, "s-", color="#ea580c", ms=5, lw=2,
            label="Browser (WebGPU)")

    # Shade the overhead region between the two curves
    common = sorted(set(ns) & set(web_ns))
    nat_interp = np.interp(common, ns, native)
    web_interp = np.interp(common, web_ns, web_t)
    ax.fill_between(common, nat_interp, web_interp, alpha=0.12,
                    color="#ea580c", label="Browser overhead")

    ax.set_xscale("log")
    ax.set_xlabel("Number of Particles ($N$)")
    ax.set_ylabel("ms / step")
    ax.set_title("Native vs. Browser Performance")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig_web_native.png"))
    plt.close(fig)

    mean_overhead = np.mean(np.array(web_interp) - np.array(nat_interp))
    print(f"  Fig 5: Web vs native \u2014 native {native[0]:.2f}\u2013{native[-1]:.2f}, "
          f"browser {web_t[0]:.2f}\u2013{web_t[-1]:.2f}, "
          f"mean overhead {mean_overhead:.1f} ms")


# ── Main ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("Generating figures...")
    fig1_n_scaling()
    fig2_crossover()
    fig3_timing_decomp()
    fig4_energy_drift()
    fig5_web_native()
    print(f"\nDone \u2014 {len(os.listdir(OUT))} PNGs in {OUT}/")
