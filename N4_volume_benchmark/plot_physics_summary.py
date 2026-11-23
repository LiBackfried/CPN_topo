#!/usr/bin/env python3
"""Plot saved N=4 correlation lengths and susceptibilities at five volumes."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, LogNorm
from matplotlib.lines import Line2D
import numpy as np


REPO = Path(__file__).resolve().parents[1]
SCAN = REPO / "N4_L66_res/volume_scan.T1n611"
LARGE = {
    90: (REPO / "N4_L90_res/combined210_ns22810844_analysis_22810847", 0.95),
    120: (REPO / "N4_L120_res/combined300_ns22885157_analysis_22904265", 1.0),
}
KEYS = ("xi_L_squared", "chi_topological")
LATTICES = (22, 38, 66, 90, 120)
REFERENCE = REPO / "N4_L66_res/reference_targets.csv"


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def load_points():
    paths = [SCAN / "volume_comparison.csv"]
    points = []
    for raw in read_csv(paths[0]):
        point = {"method": raw["method"], "L": int(float(raw["L"])),
                 "beta": float(raw["target_beta"]), "input_file": str(paths[0].relative_to(REPO)),
                 "updates": int(float(raw["updates"])) if raw["updates"] else ""}
        for key in KEYS:
            point[key] = float(raw[key])
            point[f"{key}_se"] = float(raw[f"{key}_se"])
        points.append(point)

    for lattice, (root, beta) in LARGE.items():
        depth_path, mc_path = root / "depth.csv", root / "mcmc_burn20000/binning.csv"
        paths.extend((depth_path, mc_path))
        deepest = {}
        for raw in read_csv(depth_path):
            if int(raw["L"]) != lattice:
                raise ValueError(f"Unexpected lattice in {depth_path}")
            target = float(raw["target_beta"])
            if target not in deepest or int(raw["updates"]) > int(deepest[target]["updates"]):
                deepest[target] = raw
        for target, raw in sorted(deepest.items()):
            point = {"method": "NS", "L": lattice, "beta": target,
                     "updates": int(raw["updates"]), "input_file": str(depth_path.relative_to(REPO))}
            for key in KEYS:
                point[key] = float(raw[key])
                point[f"{key}_se"] = float(raw[f"{key}_bootstrap_se"])
            points.append(point)
        mc = {raw["observable"]: raw for raw in read_csv(mc_path)
              if raw["chain"] == "pooled" and int(raw["block_size_measurements"]) == 128}
        point = {"method": "MCMC", "L": lattice, "beta": beta, "updates": "",
                 "input_file": str(mc_path.relative_to(REPO))}
        for key in KEYS:
            point[key] = float(mc[key]["estimate"])
            point[f"{key}_se"] = float(mc[key]["standard_error"])
        points.append(point)

    for point in points:
        squared = point["xi_L_squared"]
        point["xi_L"] = float(np.sqrt(squared)) if squared > 0 else np.nan
        # Use one explicit convention across all five volumes, since the large-
        # volume exports contain errors on xi squared, without bootstrap draws.
        point["xi_L_se"] = (point["xi_L_squared_se"] / (2 * point["xi_L"])
                            if squared > 0 else np.nan)
        point["L_over_xi_L"] = point["L"] / point["xi_L"]
        point["L_over_xi_L_se"] = point["L"] * point["xi_L_se"] / point["xi_L"] ** 2
        point["V"] = point["L"] ** 2
        for key in KEYS:
            if not np.isfinite(point[key]) or not np.isfinite(point[f"{key}_se"]):
                raise ValueError(f"Invalid saved value: {point}")
            if point[f"{key}_se"] < 0:
                raise ValueError(f"Negative uncertainty: {point}")
        if point["chi_topological"] <= point["chi_topological_se"]:
            raise ValueError("Susceptibility error bar cannot be drawn on a log axis")
    if len(points) != 32 or len({(p["method"], p["L"], p["beta"]) for p in points}) != 32:
        raise ValueError("Expected 27 distinct NS points and five MCMC references")
    return points, paths


def load_references():
    points = []
    for raw in read_csv(REFERENCE):
        lattice = int(raw["L"])
        if lattice not in LATTICES:
            continue
        xi, error = float(raw["xi_L"]), float(raw["xi_L_error"])
        points.append({"method": "Table III", "L": lattice, "beta": float(raw["beta"]),
                       "xi_L": xi, "xi_L_se": error, "L_over_xi_L": lattice / xi,
                       "L_over_xi_L_se": lattice * error / xi ** 2,
                       "L_over_xi_L_table_rounded": float(raw["L_over_xi_L"]),
                       "input_file": str(REFERENCE.relative_to(REPO))})
    if {p["L"] for p in points} != set(LATTICES):
        raise ValueError("Expected all five matching table volumes")
    return points


def draw_panel(ax, key, points, references, palettes, norm):
    scale = 1e4 if key == "chi_topological" else 1.0
    for lattice in LATTICES:
        for method in ("NS", "MCMC", "Table III"):
            if method == "Table III" and key == "chi_topological":
                continue  # The supplied table does not contain susceptibility.
            color = palettes[method](norm(lattice ** 2))
            source = references if method == "Table III" else points
            group = sorted((p for p in source if p["L"] == lattice and p["method"] == method),
                           key=lambda p: p["beta"])
            ax.errorbar([p["beta"] for p in group], [scale * p[key] for p in group],
                        yerr=[scale * p[f"{key}_se"] for p in group], color=color,
                        marker={"NS": "o", "MCMC": "D", "Table III": "s"}[method],
                        markerfacecolor="None", markeredgewidth=1.4,
                        markersize={"NS": 5.8, "MCMC": 10, "Table III": 7.5}[method],
                        linestyle="-" if method == "NS" else "None", linewidth=1.25,
                        elinewidth=1.0 if method == "NS" else 1.5,
                        capsize=2.5 if method == "NS" else 4,
                        zorder={"NS": 2, "MCMC": 4, "Table III": 5}[method])
    label = {"xi_L": r"Correlation length $\xi_L$",
             "L_over_xi_L": r"$L/\xi_L$",
             "chi_topological": r"Topological susceptibility $10^4\,\chi_t$"}[key]
    ax.set(xlabel=r"Target coupling $\beta$", ylabel=label, xlim=(.685, 1.015))
    ax.set_xticks(np.arange(.70, 1.001, .05))
    ax.grid(alpha=.18, linewidth=.7)
    if key == "chi_topological":
        ax.set_yscale("log")
        ax.set_ylim(.6, 60)
    else:
        ax.set_ylim(bottom=0)


def decorate(fig, palettes, norm, title):
    fig.suptitle(title, y=.98, fontsize=16)
    fig.text(.52, .90, r"NS source $\beta_0=0.70$, $\theta=0$; direct MCMC and Table III references",
             ha="center", fontsize=11)
    for method, anchor, title in (("NS", .065, "Nested sampling"),
                                  ("MCMC", .38, "MCMC"), ("Table III", .695, "Table III")):
        handles = [Line2D([], [], color=palettes[method](norm(lattice ** 2)),
                          marker={"NS": "o", "MCMC": "D", "Table III": "s"}[method],
                          markerfacecolor="None", markeredgewidth=1.4, lw=1.25,
                          linestyle="-" if method == "NS" else "None",
                          markersize=6 if method == "NS" else 8, label=rf"${lattice}^2$")
                   for lattice in LATTICES]
        fig.legend(handles=handles, title=title + r": volume $V=L^2$", loc="upper left",
                   bbox_to_anchor=(anchor, .85), ncol=5, frameon=False, handlelength=1.1,
                   columnspacing=.8, handletextpad=.35, borderaxespad=0, fontsize=9, title_fontsize=10)
    fig.text(.065, .12, r"Undefined $\xi_L$ and $L/\xi_L$ omitted: $L=38$ at $\beta=0.70$; $L=66$ at $\beta=0.70,\,0.75$.", fontsize=10)
    fig.text(.065, .078, r"Statistical $1\sigma$ errors: NS stream bootstrap; MCMC blocked jackknife. "
             r"$\sigma_{\xi}=\sigma_{\xi^2}/(2\xi)$; $\sigma_{L/\xi}=L\sigma_{\xi}/\xi^2$.", fontsize=10)
    fig.text(.065, .035, r"Table ratios are computed from tabulated $\xi_L$. Lines guide the eye; initialization and constrained-mixing checks remain open.",
             fontsize=9, color="0.35")


def plot_summary(output):
    points, paths = load_points()
    references = load_references()
    paths.append(REFERENCE)
    output.mkdir(parents=True, exist_ok=True)
    with (output / "plotted_points.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(points[0]))
        writer.writeheader()
        writer.writerows(points)
    with (output / "table_reference_points.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(references[0]))
        writer.writeheader()
        writer.writerows(references)

    plt.rcParams.update({"font.size": 11, "axes.labelsize": 13,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "svg.fonttype": "none"})
    palettes = {
        "NS": LinearSegmentedColormap.from_list("ns_volume", plt.get_cmap("Blues")(np.linspace(.40, .95, 256))),
        "MCMC": LinearSegmentedColormap.from_list("mc_volume", plt.get_cmap("Oranges")(np.linspace(.40, .95, 256))),
        "Table III": LinearSegmentedColormap.from_list("table_volume", plt.get_cmap("Greens")(np.linspace(.48, .95, 256))),
    }
    volumes = np.array([22, 38, 66, 90, 120]) ** 2
    norm = LogNorm(vmin=volumes[0], vmax=volumes[-1])
    fig, axes = plt.subplots(1, 3, figsize=(18, 6.2))
    fig.subplots_adjust(left=.065, right=.985, bottom=.235, top=.70, wspace=.30)
    for ax, key in zip(axes, ("xi_L", "L_over_xi_L", "chi_topological")):
        draw_panel(ax, key, points, references, palettes, norm)
    decorate(fig, palettes, norm, r"CP$^3$ ($N=4$): correlation lengths and topology across volumes")
    for extension in ("png", "pdf", "svg"):
        fig.savefig(output / f"correlation_length_susceptibility.{extension}", dpi=240)
    plt.close(fig)
    fig, ax = plt.subplots(figsize=(12.8, 6.2))
    fig.subplots_adjust(left=.065, right=.985, bottom=.235, top=.70)
    draw_panel(ax, "L_over_xi_L", points, references, palettes, norm)
    decorate(fig, palettes, norm, r"CP$^3$ ($N=4$): lattice size in units of the correlation length")
    for extension in ("png", "pdf", "svg"):
        fig.savefig(output / f"L_over_xi_L.{extension}", dpi=240)
    plt.close(fig)
    metadata = {
        "inputs": [{"path": str(p.relative_to(REPO)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                   for p in paths],
        "source_beta": .7, "theta": 0,
        "scope": "Main seven-beta L22/L38/L66 scans and deepest saved L90/L120 prefixes; earlier L22 narrow-beta studies excluded.",
        "NS_points": 27, "MCMC_points": 5,
        "xi_uncertainty": "First-order propagation from xi_squared for every volume and method",
        "MCMC_burn_in_MC_steps": 20000, "MCMC_block_size_measurements": 128,
        "color": "Separate Blues (NS), Oranges (MCMC), Greens (Table III) gradients, logarithmic in V=L^2; volume marker legends",
        "markers": "NS: open circles; MCMC: open diamonds; Table III: open squares; markerfacecolor='None'",
        "table_reference": "User screenshot Table III, matched to saved reference_targets.csv; only L=22,38,66,90,120 included",
        "table_reference_points": len(references),
        "table_observables": "xi_L and L/xi_L only; susceptibility not supplied",
        "ratio_uncertainty": "L*sigma_xi/xi^2; ratios computed from xi, with screenshot rounded values retained separately",
        "susceptibility_plot_scale": 1e4,
        "csv_susceptibility_scale": 1,
    }
    (output / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(points)} points and PNG/PDF/SVG to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=REPO / "N4_volume_benchmark/summary_figures_20261123")
    plot_summary(parser.parse_args().output)
