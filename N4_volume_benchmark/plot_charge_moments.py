#!/usr/bin/env python3
"""Plot charge expectation values actually exported by the saved volume scans."""

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


PANELS = (
    ("mean_Q_U", r"$\langle Q_U\rangle$"),
    ("mean_Q_z", r"$\langle Q_z\rangle$"),
    ("mean_Q_plaquette", r"$\langle Q_{\rm plaq}\rangle$"),
    ("mean_Q_U_squared", r"$\langle Q_U^2\rangle$"),
    ("mean_Q_z_squared", r"$\langle Q_z^2\rangle$"),
    ("mean_Q_plaquette_squared", r"$\langle Q_{\rm plaq}^2\rangle$"),
)


def load_charge_points():
    points, availability = [], []
    path = SCAN / "volume_comparison.csv"
    paths = [path]
    for raw in read_csv(path):
        for key, _ in PANELS:
            value, error = raw.get(key, ""), raw.get(f"{key}_se", "")
            if not value or not error:
                continue
            points.append({"method": raw["method"], "L": int(float(raw["L"])),
                           "beta": float(raw["target_beta"]), "observable": key,
                           "estimate": float(value), "standard_error": float(error),
                           "input_file": str(path.relative_to(REPO))})
    for lattice, (root, beta) in LARGE.items():
        path = root / "mcmc_burn20000/binning.csv"
        paths.append(path)
        for raw in read_csv(path):
            if (raw["chain"] == "pooled" and int(raw["block_size_measurements"]) == 128
                    and raw["observable"] in dict(PANELS)):
                points.append({"method": "MCMC", "L": lattice, "beta": beta,
                               "observable": raw["observable"], "estimate": float(raw["estimate"]),
                               "standard_error": float(raw["standard_error"]),
                               "input_file": str(path.relative_to(REPO))})
    # Prefer complete, newly exported raw-data analyses for each volume.
    # A copied partial/failed job without its completion marker is ignored.
    for lattice in LATTICES:
        parent = REPO / f"N4_L{lattice}_res/charge_moments"
        exports = [p for p in parent.glob("job_*") if p.name[4:].isdigit()
                   and (p / "completed").is_file() and (p / "charge_moments.csv").is_file()]
        if not exports:
            continue
        export = max(exports, key=lambda p: int(p.name[4:]))
        meta = json.loads((export / "inputs.json").read_text(encoding="utf-8"))
        if (meta["L"], meta["cpn_n"], meta["source_beta"], meta["theta"]) != (lattice, 4, .7, 0.):
            raise ValueError(f"Incompatible charge export: {export}")
        exported = []
        for raw in read_csv(export / "charge_moments.csv"):
            if int(raw["L"]) != lattice or raw["observable"] not in dict(PANELS):
                raise ValueError(f"Unexpected row in {export}")
            exported.append({"method": raw["method"], "L": lattice, "beta": float(raw["beta"]),
                             "observable": raw["observable"], "estimate": float(raw["estimate"]),
                             "standard_error": float(raw["standard_error"]),
                             "input_file": str((export / "charge_moments.csv").relative_to(REPO))})
        for method, betas in (("NS", meta["targets"]), ("MCMC", [meta["MCMC_beta"]])):
            expected = {(method, float(beta), key) for beta in betas for key in dict(PANELS)}
            actual = [(p["method"], p["beta"], p["observable"]) for p in exported if p["method"] == method]
            if len(actual) != len(expected) or set(actual) != expected:
                raise ValueError(f"Incomplete or duplicate charge export: {export}")
        points = [p for p in points if p["L"] != lattice] + exported
        paths.extend((export / "charge_moments.csv", export / "inputs.json"))
    for point in points:
        if not np.isfinite([point["estimate"], point["standard_error"]]).all() or point["standard_error"] < 0:
            raise ValueError(f"Invalid charge value: {point}")
    for method in ("NS", "MCMC"):
        for lattice in LATTICES:
            for key in dict(PANELS):
                count = sum(p["method"] == method and p["L"] == lattice and p["observable"] == key
                            for p in points)
                availability.append({"method": method, "L": lattice, "observable": key,
                                     "points": count, "status": "available" if count else "not_in_saved_exports"})
    return points, availability, paths


def plot_charges(output):
    points, availability, paths = load_charge_points()
    output.mkdir(parents=True, exist_ok=True)
    for name, rows in (("charge_moments_points.csv", points), ("charge_moments_availability.csv", availability)):
        with (output / name).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    plt.rcParams.update({"font.size": 11, "axes.labelsize": 14,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "svg.fonttype": "none"})
    palettes = {method: LinearSegmentedColormap.from_list(method, plt.get_cmap(name)(np.linspace(.40, .95, 256)))
                for method, name in (("NS", "Blues"), ("MCMC", "Oranges"))}
    norm = LogNorm(vmin=22 ** 2, vmax=120 ** 2)
    panels = [(key, label) for key, label in PANELS if any(p["observable"] == key for p in points)]
    columns = 3 if len(panels) > 4 else 2
    fig, axes = plt.subplots(2, columns, figsize=(18 if columns == 3 else 13.6, 8.4))
    fig.subplots_adjust(left=.08, right=.975, bottom=.18, top=.76, hspace=.36, wspace=.25)
    for ax, (key, label) in zip(axes.flat, panels):
        for method in ("NS", "MCMC"):
            for lattice in LATTICES:
                group = sorted((p for p in points if p["method"] == method and p["L"] == lattice
                                and p["observable"] == key), key=lambda p: p["beta"])
                if not group:
                    continue
                color = palettes[method](norm(lattice ** 2))
                ax.errorbar([p["beta"] for p in group], [p["estimate"] for p in group],
                            yerr=[p["standard_error"] for p in group], color=color,
                            marker="o" if method == "NS" else "D", markerfacecolor="None",
                            markeredgewidth=1.4, markersize=5.8 if method == "NS" else 9,
                            linestyle="-" if method == "NS" else "None", linewidth=1.2,
                            capsize=2.5 if method == "NS" else 4, zorder=2 if method == "NS" else 4)
        ax.set(xlabel=r"Target coupling $\beta$", ylabel=label, xlim=(.685, 1.015))
        ax.set_xticks(np.arange(.70, 1.001, .05))
        ax.grid(alpha=.18)
        if key.endswith("_squared"):
            group = [p for p in points if p["observable"] == key]
            if any(p["estimate"] <= p["standard_error"] for p in group):
                raise ValueError("Second-moment error bar cannot be drawn on a log axis")
            ax.set_yscale("log")
        else:
            ax.axhline(0, color="0.4", linestyle=":", linewidth=.9, zorder=0)
    fig.suptitle(r"CP$^3$ ($N=4$): topological-charge means and second moments", fontsize=16, y=.98)
    fig.text(.52, .925, r"NS source $\beta_0=0.70$, $\theta=0$; final recorded cooling step", ha="center")
    for method, anchor, title in (("NS", .08, "Nested sampling"), ("MCMC", .55, "MCMC")):
        lattices = sorted({p["L"] for p in points if p["method"] == method})
        handles = [Line2D([], [], color=palettes[method](norm(lattice ** 2)),
                          marker="o" if method == "NS" else "D", markerfacecolor="None",
                          linestyle="-" if method == "NS" else "None", markersize=7,
                          label=rf"${lattice}^2$") for lattice in lattices]
        fig.legend(handles=handles, title=title + r": volume $V=L^2$", loc="upper left",
                   bbox_to_anchor=(anchor, .88), ncol=5, frameon=False, handlelength=1.2,
                   columnspacing=1.0, handletextpad=.4, borderaxespad=0)
    missing = [a for a in availability if a["points"] == 0]
    ns_lattices = sorted({p["L"] for p in points if p["method"] == "NS"})
    fig.text(.08, .105, "NS volumes included: " + ", ".join(str(lattice) for lattice in ns_lattices)
             + ". MCMC markers appear where the corresponding charge was exported.", fontsize=10)
    fig.text(.08, .065, "Some moments are missing from saved exports; see charge_moments_availability.csv."
             if missing else "All three charge means and second moments are available for every NS and MCMC volume.", fontsize=10)
    fig.text(.08, .025, r"Statistical $1\sigma$ errors: NS whole-stream bootstrap; MCMC blocked jackknife. "
             r"Second moments average the measured $Q^2$.", fontsize=10, color="0.35")
    for extension in ("png", "pdf", "svg"):
        fig.savefig(output / f"charge_moments.{extension}", dpi=220)
    plt.close(fig)
    metadata = {
        "inputs": [{"path": str(p.relative_to(REPO)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths],
        "points": len(points), "source_beta": .7, "theta": 0,
        "NS_error": "whole-independent-stream bootstrap",
        "MCMC_error": "blocked jackknife; 20000 MC steps discarded, 128 measurements per block",
        "unavailable": [a for a in availability if a["points"] == 0],
        "notes": "No second moments inferred from means. No charge values supplied by screenshot Table III.",
    }
    (output / "charge_moments_provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Saved charge plots and {len(points)} exported estimates to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "N4_volume_benchmark/summary_figures_20261123")
    plot_charges(parser.parse_args().output)
