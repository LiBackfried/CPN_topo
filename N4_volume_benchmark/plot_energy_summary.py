#!/usr/bin/env python3
"""Plot N=4 intensive and extensive energy in the charge-summary style."""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, LogNorm
from matplotlib.lines import Line2D
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.plot_physics_summary import LARGE, LATTICES, REPO, SCAN, read_csv


def load_energy_points():
    paths = [SCAN / "volume_comparison.csv"]
    points = []

    def add(method, lattice, beta, value, error, path):
        if not np.isfinite([value, error]).all() or error < 0:
            raise ValueError(f"Invalid action density in {path}")
        points.append({"method": method, "L": lattice, "V": lattice ** 2, "beta": beta,
                       "mean_action_density": value, "mean_action_density_se": error,
                       "mean_energy": 2 * value, "mean_energy_se": 2 * error,
                       "mean_extensive_energy": 8 * lattice ** 2 * value,
                       "mean_extensive_energy_se": 8 * lattice ** 2 * error,
                       "input_file": str(path.relative_to(REPO))})

    for raw in read_csv(paths[0]):
        add(raw["method"], int(float(raw["L"])), float(raw["target_beta"]),
            float(raw["mean_action_density"]), float(raw["mean_action_density_se"]), paths[0])
    for lattice, (root, beta) in LARGE.items():
        path = root / "depth.csv"
        paths.append(path)
        deepest = {}
        for raw in read_csv(path):
            if int(raw["L"]) != lattice:
                raise ValueError(f"Unexpected volume in {path}")
            target = float(raw["target_beta"])
            if target not in deepest or int(raw["updates"]) > int(deepest[target]["updates"]):
                deepest[target] = raw
        for target, raw in sorted(deepest.items()):
            add("NS", lattice, target, float(raw["mean_action_density"]),
                float(raw["mean_action_density_bootstrap_se"]), path)
        path = root / "mcmc_burn20000/binning.csv"
        paths.append(path)
        selected = [raw for raw in read_csv(path) if raw["chain"] == "pooled"
                    and int(raw["block_size_measurements"]) == 128 and raw["observable"] == "mean_action_density"]
        if len(selected) != 1:
            raise ValueError(f"Expected one pooled action estimate at block size 128 in {path}")
        raw = selected[0]
        add("MCMC", lattice, beta, float(raw["estimate"]), float(raw["standard_error"]), path)
    if len(points) != 32 or len({(p["method"], p["L"], p["beta"]) for p in points}) != 32:
        raise ValueError("Expected 27 distinct NS points and five direct MCMC points")
    return points, paths


def plot_energy(output):
    points, paths = load_energy_points()
    output.mkdir(parents=True, exist_ok=True)
    with (output / "energy_points.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(points[0]))
        writer.writeheader()
        writer.writerows(points)
    plt.rcParams.update({"font.size": 11, "axes.labelsize": 13,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "svg.fonttype": "none"})
    palettes = {method: LinearSegmentedColormap.from_list(method, plt.get_cmap(name)(np.linspace(.40, .95, 256)))
                for method, name in (("NS", "Blues"), ("MCMC", "Oranges"))}
    norm = LogNorm(vmin=22 ** 2, vmax=120 ** 2)
    fig, axes = plt.subplots(1, 2, figsize=(13.6, 5.8))
    fig.subplots_adjust(left=.08, right=.975, bottom=.20, top=.70, wspace=.26)
    panels = (("mean_energy", r"Intensive energy $\langle E\rangle$", 1.),
              ("mean_extensive_energy", r"Extensive energy $\langle H\rangle/10^4$", 1e-4))
    for ax, (key, label, scale) in zip(axes, panels):
        for method in ("NS", "MCMC"):
            for lattice in LATTICES:
                group = sorted((p for p in points if p["method"] == method and p["L"] == lattice),
                               key=lambda p: p["beta"])
                color = palettes[method](norm(lattice ** 2))
                ax.errorbar([p["beta"] for p in group], [scale * p[key] for p in group],
                            yerr=[scale * p[f"{key}_se"] for p in group], color=color,
                            marker="o" if method == "NS" else "D", markerfacecolor="None",
                            markeredgewidth=1.4, markersize=5.8 if method == "NS" else 9,
                            linestyle="-" if method == "NS" else "None", linewidth=1.2,
                            capsize=2.5 if method == "NS" else 4, zorder=2 if method == "NS" else 4)
        ax.set(xlabel=r"Target coupling $\beta$", ylabel=label, xlim=(.685, 1.015))
        ax.set_xticks(np.arange(.70, 1.001, .05))
        ax.grid(alpha=.18)
    fig.suptitle(r"CP$^3$ ($N=4$): energy across volumes", fontsize=16, y=.98)
    fig.text(.52, .91, r"NS source $\beta_0=0.70$, $\theta=0$; direct MCMC references", ha="center")
    for method, anchor, title in (("NS", .08, "Nested sampling"), ("MCMC", .55, "MCMC")):
        handles = [Line2D([], [], color=palettes[method](norm(lattice ** 2)),
                          marker="o" if method == "NS" else "D", markerfacecolor="None",
                          linestyle="-" if method == "NS" else "None", markersize=7,
                          label=rf"${lattice}^2$") for lattice in LATTICES]
        fig.legend(handles=handles, title=title + r": volume $V=L^2$", loc="upper left",
                   bbox_to_anchor=(anchor, .85), ncol=5, frameon=False, handlelength=1.2,
                   columnspacing=1.0, handletextpad=.4, borderaxespad=0)
    fig.text(.08, .085, r"Normalization: $E=2\epsilon$, $H=NVE=2NV\epsilon$, $N=4$. "
             r"The dimensionless action is $S_\beta=\beta H$.", fontsize=10)
    fig.text(.08, .035, r"Statistical $1\sigma$ errors: NS whole-stream bootstrap; MCMC blocked jackknife. Lines guide the eye.",
             fontsize=10, color=".35")
    for extension in ("png", "pdf", "svg"):
        path = output / f"energy_summary.{extension}"
        fig.savefig(path, dpi=230)
        if extension == "svg":
            path.write_text("\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()) + "\n",
                            encoding="utf-8", newline="\n")
    plt.close(fig)
    metadata = {
        "inputs": [{"path": str(path.relative_to(REPO)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths],
        "NS_points": 27, "MCMC_points": 5, "source_beta": .7, "theta": 0, "cpn_n": 4,
        "definitions": {"mean_energy": "2*mean_action_density", "mean_extensive_energy": "2*N*V*mean_action_density"},
        "extensive_energy_display_scale": 1e-4, "CSV_values": "unscaled",
        "uncertainty": "The same exact multiplicative factors applied to the saved statistical errors",
        "NS_error": "whole-independent-stream bootstrap",
        "MCMC_error": "blocked jackknife, 20000-step burn-in and 128-measurement blocks",
        "style": "Open circles/Blues for NS; open diamonds/Oranges for MCMC; gradients track volume",
    }
    (output / "energy_provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Saved energy plots and {len(points)} estimates to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "N4_volume_benchmark/summary_figures_20261123")
    plot_energy(parser.parse_args().output)
