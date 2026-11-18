#!/usr/bin/env python3
"""Overlay normalized source/reweighted quadrature weights for one N=4 NS run."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import to_rgb
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.scan_depth import load_chain
from utils.nest_sampl import NestedSamplingStream, combine_streams, reweight_beta


BETAS = (0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0)


def single_run_weights(action_density, lattice, n_live, targets=BETAS):
    """Normalize each beta curve over every measured dead point in one stream."""
    epsilon = np.asarray(action_density, dtype=float)
    if epsilon.ndim != 1 or not len(epsilon) or not np.isfinite(epsilon).all():
        raise ValueError("expected a nonempty finite action-density series")
    if lattice < 2 or n_live < 1:
        raise ValueError("require L >= 2 and a positive live-point count")
    betas = np.asarray(targets, dtype=float)
    if (betas.ndim != 1 or not len(betas) or not np.isfinite(betas).all()
            or np.any(betas < 0.7) or len(set(betas)) != len(betas)):
        raise ValueError("use distinct finite target betas >= source beta 0.7")
    stream = NestedSamplingStream(2 * epsilon, {"action_density": epsilon}, n_live)
    source = combine_streams([stream])
    logs = np.array([reweight_beta(source, 0.7, beta, 4, lattice**2)[0].log_weight_normalized
                     for beta in betas])
    return {"rank": np.arange(len(epsilon)), "action_density": source.observables["action_density"],
            "betas": betas, "normalized_weight": np.exp(logs),
            "log_normalized_weight": logs, "log_x": source.log_x}


def plot_single_run_weights(action_density, lattice, n_live, output, run=None, rng_seed=None):
    data = single_run_weights(action_density, lattice, n_live)
    output.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(output / "normalized_weights_single_run.npz", **data)
    provenance = {"run": str(run) if run is not None else None, "rng_seed": rng_seed,
                  "L": lattice, "N": 4, "source_beta": 0.7, "num_live_pts": n_live,
                  "points": len(data["rank"]), "betas": list(BETAS),
                  "normalization_sums": data["normalized_weight"].sum(axis=1).tolist(),
                  "support": "full selected single stream, including initial and final measurements",
                  "display": "x range through at least 99.99 percent mass for every beta"}
    (output / "normalized_weights_single_run.json").write_text(
        json.dumps(provenance, indent=2), encoding="utf-8")
    # Keep all original points; only the display range is shortened. This avoids
    # missing a narrow peak through plot thinning or changing per-point weights.
    cumulative = np.cumsum(data["normalized_weight"], axis=1)
    last_rank = max(min(np.searchsorted(curve, 0.9999), len(curve)-1) for curve in cumulative)
    xmax = max(1, min(len(data["rank"])-1, last_rank * 1.025))
    crimson = np.array(to_rgb("crimson"))
    colors = [crimson] + [tuple((1 - t) * np.ones(3) + t * crimson)
                          for t in np.linspace(0.4, 1.0, len(BETAS)-1)]
    styles = ["-", "--", "-.", ":", "--", "-.", ":"]
    for logarithmic in (False, True):
        fig, ax = plt.subplots(figsize=(10, 5.4))
        fig.subplots_adjust(left=0.11, right=0.98, bottom=0.13, top=0.80)
        for index, beta in enumerate(BETAS):
            label = rf"$\beta={beta:.2f}$" + (" (source)" if index == 0 else "")
            # Base-10 logarithms retain underflowed tails without exp/log loss.
            values = (data["log_normalized_weight"][index] / np.log(10)
                      if logarithmic else data["normalized_weight"][index])
            ax.plot(data["rank"], values, color=colors[index], linestyle=styles[index],
                    linewidth=2.0 if index == 0 else 1.6, label=label)
        ax.set(xlim=(0, xmax), xlabel="Dead-point rank (0 = initial measurement)",
               ylabel=r"$\log_{10} p_i(\beta)$" if logarithmic else r"Normalized weight $p_i(\beta)$")
        if logarithmic:
            peak = np.max(data["log_normalized_weight"]) / np.log(10)
            ax.set_ylim(peak-9, peak+0.25)
        else:
            ax.set_ylim(bottom=0)
            ax.ticklabel_format(axis="y", style="sci", scilimits=(-3, 3))
        run_label = f"{Path(run).parent.name}/{Path(run).name}" if run is not None else "single stream"
        fig.suptitle(f"N=4, L={lattice}: {run_label}" +
                     (f", seed={rng_seed}" if rng_seed is not None else ""), y=0.98, fontsize=13)
        ax.set_title(r"$\sum_i p_i(\beta)=1$ separately for every curve; source $\beta_0=0.7$",
                     fontsize=11, pad=12)
        ax.legend(ncol=2, fontsize=9, loc="lower left" if logarithmic else "upper right")
        ax.grid(alpha=0.2)
        stem = "normalized_weights_single_run" + ("_log" if logarithmic else "")
        for suffix in ("png", "pdf"):
            fig.savefig(output / f"{stem}.{suffix}", dpi=180)
        plt.close(fig)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--run", type=Path, help="One run directory (continuation history is followed)")
    source.add_argument("--analysis", type=Path, help="L22 or L38 scan directory; use its first selected stream")
    parser.add_argument("--output", type=Path, help="Defaults to --analysis; required with --run")
    args = parser.parse_args()
    output = args.output or args.analysis
    if output is None:
        parser.error("--run requires --output")
    try:
        run = args.run
        if args.analysis is not None:
            manifest = args.analysis / "inputs.json"
            paths = (json.loads(manifest.read_text())["runs"] if manifest.is_file()
                     else (args.analysis / "selected_runs.txt").read_text().splitlines())
            if not paths:
                raise ValueError("No selected streams recorded in the analysis directory")
            run = Path(paths[0])
        run = run.expanduser().resolve()
        config, chain = load_chain(run)
        lattice, other = map(int, config["size"])
        if (lattice != other or float(config["beta"][0]) != 0.7 or float(config["theta"][0]) != 0):
            raise ValueError("Expected square N=4 data at source beta=0.7, theta=0")
        plot_single_run_weights(chain[:, 0], lattice, int(config["num_live_pts"][0]), output,
                                run=run, rng_seed=int(config["rng_seed"][0]))
        print(f"Saved single-stream weight overlays to {output}")
    except (ValueError, OSError, KeyError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
