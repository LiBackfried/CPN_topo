#!/usr/bin/env python3
"""Plot saved N=4 correlation lengths against V=L^2, at fixed and table-matched beta."""

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
from matplotlib.ticker import FixedLocator, FixedFormatter, NullLocator
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.plot_physics_summary import LATTICES, REFERENCE, REPO, load_points, load_references


MARKERS = {"NS": "o", "MCMC": "D", "Table III": "s"}
SIZES = {"NS": 6, "MCMC": 10, "Table III": 7.5}


def palettes_and_norm():
    palettes = {method: LinearSegmentedColormap.from_list(method, plt.get_cmap(name)(np.linspace(low, .95, 256)))
                for method, name, low in (("NS", "Blues", .40), ("MCMC", "Oranges", .40),
                                          ("Table III", "Greens", .48))}
    return palettes, LogNorm(vmin=22 ** 2, vmax=120 ** 2)


def draw_points(ax, points, palettes, norm, connect_ns=True):
    for method in MARKERS:
        group = sorted((p for p in points if p["method"] == method and np.isfinite(p["xi_L"])),
                       key=lambda p: p["L"])
        if method == "NS" and connect_ns and len(group) > 1:
            ax.plot([p["L"] ** 2 for p in group], [p["xi_L"] for p in group],
                    color=palettes[method](.55), linewidth=1.1, alpha=.75, zorder=1)
        for point in group:
            ax.errorbar(point["L"] ** 2, point["xi_L"], yerr=point["xi_L_se"],
                        color=palettes[method](norm(point["L"] ** 2)), marker=MARKERS[method],
                        markerfacecolor="None", markeredgewidth=1.4, markersize=SIZES[method],
                        linestyle="None", capsize=2.5 if method == "NS" else 4,
                        elinewidth=1.1, zorder={"NS": 2, "MCMC": 4, "Table III": 5}[method])
    ax.set_xscale("log")
    ax.set_xlim(380, 18300)
    ax.xaxis.set_major_locator(FixedLocator([lattice ** 2 for lattice in LATTICES]))
    ax.xaxis.set_major_formatter(FixedFormatter([rf"${lattice}^2$" for lattice in LATTICES]))
    ax.xaxis.set_minor_locator(NullLocator())
    ax.set(xlabel=r"Volume $V=L^2$", ylabel=r"$\xi_L$")
    ax.grid(alpha=.18, linewidth=.7)


def legend_handles(method, palettes, norm):
    return [Line2D([], [], color=palettes[method](norm(lattice ** 2)),
                   marker=MARKERS[method], markerfacecolor="None", markeredgewidth=1.4,
                   markersize=6 if method == "NS" else 7, linestyle="None",
                   label=rf"${lattice}^2$") for lattice in LATTICES]


def save_figure(fig, output, stem):
    for extension in ("png", "pdf", "svg"):
        path = output / f"{stem}.{extension}"
        fig.savefig(path, dpi=230)
        if extension == "svg":
            # Matplotlib adds trailing spaces to SVG path lines.
            cleaned = "\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()) + "\n"
            path.write_text(cleaned, encoding="utf-8", newline="\n")
    plt.close(fig)


def plot_volume(output):
    points, paths = load_points()
    references = load_references()
    all_points = points + references
    output.mkdir(parents=True, exist_ok=True)
    exported = [{"method": p["method"], "L": p["L"], "V": p["L"] ** 2, "beta": p["beta"],
                 "xi_L": p["xi_L"], "xi_L_se": p["xi_L_se"],
                 "status": "plotted" if np.isfinite(p["xi_L"]) else "undefined_xi_omitted",
                 "input_file": p["input_file"]} for p in all_points]
    with (output / "xi_L_vs_volume_points.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(exported[0]))
        writer.writeheader()
        writer.writerows(exported)
    plt.rcParams.update({"font.size": 10, "axes.labelsize": 12,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "svg.fonttype": "none"})
    palettes, norm = palettes_and_norm()
    betas = sorted({p["beta"] for p in points if p["method"] == "NS"})
    fig, axes = plt.subplots(2, 4, figsize=(16.8, 8.2))
    fig.subplots_adjust(left=.06, right=.985, bottom=.14, top=.86, hspace=.43, wspace=.31)
    for ax, beta in zip(axes.flat, betas):
        group = [p for p in all_points if np.isclose(p["beta"], beta, rtol=0, atol=1e-12)]
        draw_points(ax, group, palettes, norm)
        ax.set_title(rf"$\beta={beta:.2f}$", fontsize=13)
        missing = [str(p["L"]) for p in group if p["method"] == "NS" and not np.isfinite(p["xi_L"])]
        if missing:
            ax.text(.04, .97, "Undefined: L=" + ", ".join(missing), transform=ax.transAxes,
                    va="top", fontsize=8, color=".35")
            lower, upper = ax.get_ylim()
            ax.set_ylim(lower, upper + .12 * (upper - lower))
    legend_ax = axes.flat[-1]
    legend_ax.axis("off")
    legend_ax.text(.03, .98, r"Open markers; volume $V=L^2$", transform=legend_ax.transAxes, va="top", fontsize=11)
    for method, anchor, title in (("NS", .85, "Nested sampling"), ("MCMC", .58, "MCMC"),
                                  ("Table III", .31, "Table III")):
        legend = legend_ax.legend(handles=legend_handles(method, palettes, norm), title=title,
                                  loc="upper left", bbox_to_anchor=(0, anchor), ncol=5, frameon=False,
                                  handlelength=.85, columnspacing=.45, handletextpad=.25,
                                  fontsize=8, title_fontsize=10, borderaxespad=0)
        legend_ax.add_artist(legend)
    fig.suptitle(r"CP$^3$ ($N=4$): correlation length versus volume at fixed coupling", fontsize=17, y=.975)
    fig.text(.52, .918, r"NS source $\beta_0=0.70$, $\theta=0$; direct MCMC and matching Table III points", ha="center", fontsize=11)
    fig.text(.06, .065, r"Statistical $1\sigma$ errors; $\sigma_\xi=\sigma_{\xi^2}/(2\xi)$. "
             "Volume axis is logarithmic; panels use separate vertical scales.", fontsize=10)
    fig.text(.06, .025, r"NS lines guide the eye at fixed $\beta$. Undefined square roots are omitted; unavailable volume/coupling pairs are not filled.",
             fontsize=10, color=".35")
    save_figure(fig, output, "xi_L_vs_volume")

    # Also preserve the comparison at the user's five Table III target pairs.
    target_pairs = {(p["L"], p["beta"]) for p in references}
    matched = [p for p in all_points if (p["L"], p["beta"]) in target_pairs]
    fig, ax = plt.subplots(figsize=(12.8, 6.3))
    fig.subplots_adjust(left=.08, right=.98, bottom=.17, top=.70)
    draw_points(ax, matched, palettes, norm, connect_ns=False)
    for lattice, beta in sorted(target_pairs):
        ax.text(lattice ** 2, .98, rf"$\beta={beta:.2f}$", transform=ax.get_xaxis_transform(),
                ha="center", va="top", fontsize=10, color=".35")
    lower, upper = ax.get_ylim()
    ax.set_ylim(lower, upper + .10 * (upper - lower))
    fig.suptitle(r"CP$^3$ ($N=4$): correlation lengths at the Table III target pairs", fontsize=16, y=.975)
    fig.text(.52, .91, r"Target $\beta$ is chosen separately for each volume, as annotated", ha="center", fontsize=11)
    for method, anchor in (("NS", .08), ("MCMC", .395), ("Table III", .71)):
        fig.legend(handles=legend_handles(method, palettes, norm), title=("Nested sampling" if method == "NS" else method),
                   loc="upper left", bbox_to_anchor=(anchor, .85), ncol=5, frameon=False,
                   handlelength=1, columnspacing=.7, handletextpad=.3, fontsize=9, borderaxespad=0)
    fig.text(.08, .07, r"Open markers and statistical $1\sigma$ errors. Volume axis is logarithmic. "
             r"The direct $L=38$ MCMC reference is at $\beta=1.00$ and is absent here.", fontsize=10)
    save_figure(fig, output, "xi_L_vs_volume_table_targets")

    metadata = {
        "inputs": [{"path": str(path.relative_to(REPO)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                   for path in [*paths, REFERENCE]],
        "source_beta": .7, "theta": 0, "volume": "V=L^2; logarithmic x axis",
        "fixed_beta_panels": betas, "NS_points": 27, "MCMC_points": 5, "table_reference_points": 5,
        "undefined_NS_points_omitted": [{"L": p["L"], "beta": p["beta"]} for p in points if not np.isfinite(p["xi_L"])],
        "xi_uncertainty": "First-order propagation from xi_squared; reference uncertainties as tabulated",
        "matched_target_pairs": [{"L": lattice, "beta": beta} for lattice, beta in sorted(target_pairs)],
        "style": "Open circles/Blues for NS; open diamonds/Oranges for MCMC; open squares/Greens for Table III; gradients track volume",
    }
    (output / "xi_L_vs_volume_provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Saved fixed-beta and table-target volume plots to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "N4_volume_benchmark/summary_figures_20261123")
    plot_volume(parser.parse_args().output)
