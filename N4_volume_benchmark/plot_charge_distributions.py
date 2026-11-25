#!/usr/bin/env python3
"""Export weighted N=4 charge histograms from scratch and plot them from CSV."""

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
from N4_volume_benchmark.export_charge_moments import (
    CHARGES, PLANS, campaign_inputs, load_mc_charges, scratch_path,
)
from N4_volume_benchmark.scan_depth import common_prefix, load_ns_ensemble
from utils.cpn_io import discover_runs
from utils.nest_sampl import NestedSamplingStream, bootstrap_nested_sampling, reweight_beta


REPO = Path(__file__).resolve().parents[1]
LATTICES = (22, 38, 66, 90, 120)
LATEST_L120 = REPO / "N4_L120_res/combined24x300_analysis_23350708/inputs.tsv"
LABELS = {"Q_U": r"$Q_U$", "Q_z": r"$Q_z$", "Q_plaquette": r"$Q_{\rm plaq}$"}


def distribution_inputs(lattice, scratch, manifest=None):
    """Use prior selections, with the completed 24-stream L120 update by default."""
    if manifest is None and lattice == 120 and LATEST_L120.is_file() and (LATEST_L120.parent / "completed").is_file():
        manifest = LATEST_L120
    if manifest is None:
        return campaign_inputs(lattice, scratch)
    _, updates, proposals, mc_beta, mc_relative = PLANS[lattice]
    targets = (.9, .95, 1.) if lattice >= 90 else (.7, .75, .8, .85, .9, .95, 1.)
    if manifest.suffix == ".json":
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if "L" in data and int(data["L"]) != lattice:
            raise ValueError("Manifest belongs to a different lattice")
        if "NS_paths" not in data and "runs" not in data:
            raise ValueError("JSON manifest needs NS_paths or runs")
        saved_paths = data.get("NS_paths", data.get("runs"))
        updates = int(data.get("updates", data.get("depth", updates)))
        targets = tuple(data.get("targets", data.get("betas", targets)))
        mc_beta = float(data.get("MCMC_beta", mc_beta))
        if data.get("MCMC_chains"):
            parents = {str(Path(row["path"]).parent) for row in data["MCMC_chains"]}
            if len(parents) != 1:
                raise ValueError("MCMC chains must share one job root")
            mc_root = scratch_path(parents.pop(), scratch)
        else:
            mc_root = scratch / mc_relative
    else:
        with manifest.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        saved_paths = [row["directory"] for row in rows if row["kind"] == "ns"]
        mc_rows = [row for row in rows if row["kind"] == "mcmc"]
        if len(mc_rows) != 1 or not saved_paths:
            raise ValueError("TSV manifest needs NS roots and exactly one MCMC root")
        mc_root = scratch_path(mc_rows[0]["directory"], scratch)
    paths = discover_runs([scratch_path(path, scratch) for path in saved_paths])
    if not mc_root.is_dir():
        raise FileNotFoundError(mc_root)
    return paths, mc_root, targets, updates, proposals, mc_beta, manifest


def bin_indices(values, edges):
    values = np.asarray(values)
    if not np.isfinite(values).all():
        raise ValueError("Charges must be finite")
    indices = np.searchsorted(edges, values, side="right") - 1
    # numpy.histogram includes the rightmost edge in its final bin.
    indices = np.where(values == edges[-1], len(edges) - 2, indices)
    if np.any(indices < 0) or np.any(indices >= len(edges) - 1):
        raise ValueError("Bin edges do not include every charge measurement")
    return indices.astype(np.int64)


def charge_edges(streams, mc_chains, width=1., max_bins=1001):
    if not np.isfinite(width) or width <= 0 or max_bins < 1:
        raise ValueError("Use a positive bin width and max-bin count")
    edges = {}
    for column, (name, observable) in enumerate(CHARGES):
        ranges = [(s.observables[observable].min(), s.observables[observable].max()) for s in streams]
        ranges += [(q[:, column].min(), q[:, column].max()) for q in mc_chains]
        lower = int(np.floor(min(pair[0] for pair in ranges) / width + .5))
        upper = int(np.floor(max(pair[1] for pair in ranges) / width + .5))
        if upper - lower + 1 > max_bins:
            raise ValueError(f"{name} needs {upper-lower+1} bins; increase --bin-width or --max-bins")
        edges[name] = (np.arange(lower, upper + 2, dtype=float) - .5) * width
    return edges


def histogram_streams(streams, edges):
    """Carry fixed bin IDs through the usual remerge without rounding charges."""
    return [NestedSamplingStream(stream.energy,
            {"action_density": stream.observables["action_density"],
             **{f"{name}_bin": bin_indices(stream.observables[observable], edges[name])
                for name, observable in CHARGES}}, stream.n_live, stream.name) for stream in streams]


def ns_histogram_statistic(data, lattice, targets, edges):
    values = {}
    indices = {name: data.observables[f"{name}_bin"].astype(np.int64) for name, _ in CHARGES}
    for beta in targets:
        target, _, _ = reweight_beta(data, .7, beta, 4, lattice ** 2)
        weights = target.weight
        for name, _ in CHARGES:
            # bincount adds positive weights directly, avoiding differences of
            # cumulative sums that can erase small probabilities in tail bins.
            probability = np.bincount(indices[name], weights=weights, minlength=len(edges[name]) - 1)
            if not np.isclose(probability.sum(), 1., rtol=0, atol=1e-10):
                raise ValueError("NS histogram is not normalized")
            values.update({f"{beta}/{name}/{i}": float(value) for i, value in enumerate(probability)})
    return values


def mc_histograms(chains, edges, block_size):
    """Histogram contiguous MC blocks, then delete one complete block at a time."""
    if block_size < 1:
        raise ValueError("Block size must be positive")
    estimates, errors = {}, {}
    dropped = [len(q) % block_size for q in chains]
    for column, (name, _) in enumerate(CHARGES):
        bins = len(edges[name]) - 1
        blocks = []
        for q in chains:
            n_blocks = len(q) // block_size
            if n_blocks < 16:
                raise ValueError("Each MCMC chain needs at least sixteen complete blocks")
            n = n_blocks * block_size
            ids = bin_indices(q[:n, column], edges[name])
            flat = ids + bins * (np.arange(n) // block_size)
            counts = np.bincount(flat, minlength=n_blocks * bins).reshape(n_blocks, bins)
            blocks.append(counts / block_size)
        blocks = np.concatenate(blocks)
        n_blocks = len(blocks)
        total = blocks.sum(axis=0)
        estimates[name] = total / n_blocks
        replicates = (total - blocks) / (n_blocks - 1)
        errors[name] = np.sqrt(n_blocks - 1) * replicates.std(axis=0)
    return estimates, errors, n_blocks, dropped


def validate_histogram_rows(rows):
    groups = {}
    widths = {}
    for row in rows:
        key = (row["method"], row["L"], row["beta"], row["charge"])
        if row["method"] not in ("NS", "MCMC") or row["charge"] not in LABELS:
            raise ValueError("Unexpected histogram method or charge")
        numeric = [row[k] for k in ("beta", "bin_left", "bin_right", "bin_center", "probability", "standard_error")]
        if (not np.isfinite(numeric).all() or row["probability"] < 0 or row["standard_error"] < 0
                or row["bin_right"] <= row["bin_left"]
                or not np.isclose(row["bin_center"], (row["bin_left"] + row["bin_right"]) / 2)):
            raise ValueError("Invalid histogram bin or probability")
        groups.setdefault(key, []).append(row)
    for key, group in groups.items():
        group.sort(key=lambda row: row["bin_index"])
        if [r["bin_index"] for r in group] != list(range(len(group))):
            raise ValueError(f"Duplicate or incomplete histogram: {key}")
        if not np.isclose(sum(r["probability"] for r in group), 1., rtol=0, atol=1e-10):
            raise ValueError(f"Histogram does not sum to one: {key}")
        if any(not np.isclose(a["bin_right"], b["bin_left"]) for a, b in zip(group, group[1:])):
            raise ValueError(f"Non-contiguous histogram bins: {key}")
        bin_width = group[0]["bin_right"] - group[0]["bin_left"]
        if any(not np.isclose(r["bin_right"] - r["bin_left"], bin_width) for r in group):
            raise ValueError("Use uniform charge bins")
        if key[3] in widths and not np.isclose(widths[key[3]], bin_width):
            raise ValueError("Use the same bin width when comparing volume distributions")
        widths[key[3]] = bin_width
    if not groups:
        raise ValueError("No histogram rows")
    for key in {key[:3] for key in groups}:
        if {group[3] for group in groups if group[:3] == key} != set(LABELS):
            raise ValueError(f"Missing charge definitions for {key}")
    return groups


def render_distributions(rows, output, probability_floor=1e-6):
    if not 0 < probability_floor < 1:
        raise ValueError("Probability floor must lie between zero and one")
    groups = validate_histogram_rows(rows)
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.size": 11, "axes.labelsize": 13,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42})
    palettes = {method: LinearSegmentedColormap.from_list(method, plt.get_cmap(name)(np.linspace(.40, .95, 256)))
                for method, name in (("NS", "Blues"), ("MCMC", "Oranges"))}
    norm = LogNorm(vmin=22 ** 2, vmax=120 ** 2)
    for beta in sorted({key[2] for key in groups}):
        active = {key: value for key, value in groups.items() if key[2] == beta}
        for scale in ("linear", "log"):
            fig, axes = plt.subplots(1, 3, figsize=(16.5, 5.8))
            fig.subplots_adjust(left=.065, right=.985, bottom=.20, top=.70, wspace=.28)
            for ax, (charge, _) in zip(axes, CHARGES):
                for (method, lattice, _, name), group in sorted(active.items()):
                    if name != charge:
                        continue
                    probability = np.array([r["probability"] for r in group])
                    errors = np.array([r["standard_error"] for r in group])
                    centers = np.array([r["bin_center"] for r in group])
                    color = palettes[method](norm(lattice ** 2))
                    displayed = probability > 0 if scale == "log" else np.ones(len(group), dtype=bool)
                    # Keep zero-probability gaps in the connecting line.
                    line_y = np.where(displayed, probability, np.nan)
                    ax.plot(centers, line_y, color=color, linewidth=1, alpha=.65)
                    ax.errorbar(centers[displayed], probability[displayed], yerr=errors[displayed],
                                color=color, marker="o" if method == "NS" else "D", markerfacecolor="None",
                                markeredgewidth=1.2, markersize=4.5 if method == "NS" else 6.5,
                                linestyle="None", capsize=2, zorder=3 if method == "NS" else 4)
                ax.set(xlabel=LABELS[charge], ylabel="Probability per bin")
                ax.grid(alpha=.18)
                if scale == "log":
                    ax.set_yscale("log", nonpositive="mask")
                    ax.set_ylim(probability_floor, 1.2)
                else:
                    ax.set_ylim(bottom=0)
            fig.suptitle(rf"CP$^3$ ($N=4$): charge distributions at $\beta={beta:.4g}$", fontsize=16, y=.98)
            fig.text(.52, .91, r"NS source $\beta_0=0.70$, $\theta=0$; MCMC shown only at its direct coupling", ha="center")
            for method, anchor, title in (("NS", .065, "Nested sampling"), ("MCMC", .55, "MCMC")):
                lattices = sorted({key[1] for key in active if key[0] == method})
                if not lattices:
                    continue
                handles = [Line2D([], [], color=palettes[method](norm(lattice ** 2)),
                                  marker="o" if method == "NS" else "D", markerfacecolor="None",
                                  linestyle="None", markersize=6, label=rf"${lattice}^2$") for lattice in lattices]
                fig.legend(handles=handles, title=title + r": volume $V=L^2$", loc="upper left",
                           bbox_to_anchor=(anchor, .85), ncol=5, frameon=False, columnspacing=.9,
                           handlelength=1.1, handletextpad=.35, borderaxespad=0)
            fig.text(.065, .085, r"Normalized bin probabilities; raw charges are binned without rounding. "
                     r"Statistical $1\sigma$ errors: NS stream bootstrap, MCMC block jackknife.", fontsize=10)
            fig.text(.065, .035, f"Log view displays probabilities from {probability_floor:g} to 1; zero bins and nonpositive error-bar limits are masked."
                     if scale == "log" else "Bin probabilities sum to one for every method, volume, coupling and charge definition.",
                     fontsize=10, color=".35")
            tag = f"{beta:.6g}".replace(".", "p")
            for suffix in ("png", "pdf"):
                fig.savefig(output / f"charge_distributions_beta{tag}_{scale}.{suffix}", dpi=200)
            plt.close(fig)


def analyze_distributions(ns_paths, mc_root, output, lattice, targets, updates, proposals, mc_beta,
                          bootstrap=200, seed=20261125, burn_in=20000, block_size=128,
                          bin_width=1., max_bins=1001, manifest=None, probability_floor=1e-6):
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite {output}")
    if (bootstrap < 2 or seed < 0 or burn_in < 0 or block_size < 1 or not 0 < probability_floor < 1
            or updates < 1 or not targets or len(set(targets)) != len(targets)
            or any(not np.isfinite(beta) for beta in targets)):
        raise ValueError("Require >=2 bootstraps, positive depth/block size, and distinct finite target betas")
    mc_chains, mc_info = load_mc_charges(mc_root, lattice, mc_beta, burn_in) if mc_root is not None else ([], [])
    config, chains = load_ns_ensemble(ns_paths)
    if (tuple(map(int, config["size"])) != (lattice, lattice)
            or int(config["num_single_site_stoc_upd"][0]) != proposals):
        raise ValueError("NS settings do not match requested lattice/proposal count")
    if min(len(q) - 1 for q in chains) < updates:
        raise ValueError("NS streams do not reach the requested depth")
    cooling = int(config["num_cool_step"][0])
    if any(info["cooling_step"] != cooling for info in mc_info):
        raise ValueError("NS and MCMC must use the same recorded cooling step")
    streams = common_prefix(chains, updates, int(config["num_live_pts"][0]))
    del chains
    edges = charge_edges(streams, mc_chains, bin_width, max_bins)
    binned_streams = histogram_streams(streams, edges)
    del streams
    mc_est, mc_se, blocks, dropped = mc_histograms(mc_chains, edges, block_size) if mc_chains else ({}, {}, 0, [])
    del mc_chains
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"L": lattice, "cpn_n": 4, "source_beta": .7, "theta": 0,
                "targets": list(targets), "updates": updates, "NS_streams": len(binned_streams),
                "proposals": proposals, "NS_paths": [str(p) for p in ns_paths], "MCMC_beta": mc_beta,
                "MCMC_chains": mc_info, "cooling_step": cooling, "bootstrap": bootstrap, "seed": seed,
                "burn_in_MC_steps": burn_in, "block_size_measurements": block_size,
                "MCMC_complete_blocks": blocks, "MCMC_dropped_tail_measurements": dropped,
                "bin_width": bin_width, "bin_edges": {name: value.tolist() for name, value in edges.items()},
                "normalization": "Probability per bin, sum=1; not density per unit Q; no charge rounding",
                "NS_error": "Whole-stream bootstrap; every replicate remerges and recomputes canonical weights",
                "MCMC_error": "Delete-one-complete-block jackknife; no blocks cross chains",
                "support": "Same common-energy-support prefix convention as the saved volume scans",
                "probability_floor_for_log_plot": probability_floor}
    if manifest is not None:
        metadata["selection_manifest"] = str(manifest)
        metadata["selection_manifest_sha256"] = hashlib.sha256(manifest.read_bytes()).hexdigest()
    (output / "inputs.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"L{lattice}: bootstrapping histograms from {len(binned_streams)} streams at {updates} updates", flush=True)
    estimates, errors, _ = bootstrap_nested_sampling(
        binned_streams, lambda data: ns_histogram_statistic(data, lattice, targets, edges), bootstrap, seed)
    rows = []
    for method, betas in (("NS", targets), ("MCMC", [mc_beta] if mc_info else [])):
        for beta in betas:
            for name, _ in CHARGES:
                for index, (left, right) in enumerate(zip(edges[name][:-1], edges[name][1:])):
                    key = f"{beta}/{name}/{index}"
                    probability = estimates[key] if method == "NS" else mc_est[name][index]
                    error = errors[key] if method == "NS" else mc_se[name][index]
                    rows.append({"method": method, "L": lattice, "beta": beta, "charge": name,
                                 "bin_index": index, "bin_left": float(left), "bin_right": float(right),
                                 "bin_center": float((left + right) / 2), "probability": float(probability),
                                 "standard_error": float(error)})
    validate_histogram_rows(rows)
    with (output / "charge_distributions.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    render_distributions(rows, output, probability_floor)
    (output / "completed").write_text("Charge distributions exported and plotted.\n", encoding="utf-8")
    print(f"Wrote distributions and plots to {output}", flush=True)


def read_histograms(paths):
    rows = []
    for path in paths:
        with path.open(newline="", encoding="utf-8") as handle:
            for raw in csv.DictReader(handle):
                rows.append({key: (int(value) if key in ("L", "bin_index") else
                                   value if key in ("method", "charge") else float(value))
                             for key, value in raw.items()})
    validate_histogram_rows(rows)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    raw = commands.add_parser("analyze", help="Read raw runs on UBELIX, export histograms, and plot")
    raw.add_argument("--lattice", type=int, choices=LATTICES, required=True)
    raw.add_argument("--scratch-root", type=Path, default=Path("/scratch/network/users/lb25v444/out_data"))
    raw.add_argument("--manifest", type=Path, help="Override default campaign with an inputs.tsv or inputs.json")
    raw.add_argument("--ns", type=Path, nargs="+", help="Explicit NS roots; allows local NS-only analysis")
    raw.add_argument("--mc-root", type=Path, help="Explicit MCMC root; omitted in explicit --ns mode unless supplied")
    raw.add_argument("--updates", type=int)
    raw.add_argument("--targets", type=float, nargs="+")
    raw.add_argument("--bootstrap", type=int, default=200)
    raw.add_argument("--seed", type=int, default=20261125)
    raw.add_argument("--burn-in", type=int, default=20000)
    raw.add_argument("--block-size", type=int, default=128)
    raw.add_argument("--bin-width", type=float, default=1.)
    raw.add_argument("--max-bins", type=int, default=1001)
    raw.add_argument("--probability-floor", type=float, default=1e-6)
    raw.add_argument("--output", type=Path, required=True)
    plot = commands.add_parser("plot", help="Plot copied histograms without raw simulation files")
    plot.add_argument("inputs", type=Path, nargs="*", help="CSV files; default: newest completed export for each volume")
    plot.add_argument("--output", type=Path, default=REPO / "N4_volume_benchmark/charge_distribution_figures")
    plot.add_argument("--probability-floor", type=float, default=1e-6)
    args = parser.parse_args()
    if args.command == "plot":
        paths = args.inputs
        if not paths:
            paths = []
            for lattice in LATTICES:
                parent = REPO / f"N4_L{lattice}_res/charge_distributions"
                jobs = [p for p in parent.glob("job_*") if p.name[4:].isdigit()
                        and (p / "completed").is_file() and (p / "charge_distributions.csv").is_file()]
                if jobs:
                    paths.append(max(jobs, key=lambda p: int(p.name[4:])) / "charge_distributions.csv")
        if not paths:
            parser.error("No completed histogram exports found; first run analyze on the raw scratch data")
        rows = read_histograms(paths)
        render_distributions(rows, args.output, args.probability_floor)
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "plot_inputs.json").write_text(json.dumps([
            {"path": str(p.resolve()), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths], indent=2) + "\n")
        print(f"Plotted {len(paths)} histogram exports in {args.output}")
        return
    if args.ns and args.manifest:
        parser.error("Use either --ns or --manifest")
    if args.ns:
        paths = discover_runs(args.ns)
        if args.updates is None:
            parser.error("Explicit --ns mode requires --updates")
        _, updates, proposals, mc_beta, _ = PLANS[args.lattice]
        mc, targets, manifest = args.mc_root, (mc_beta,), None
    else:
        paths, mc, targets, updates, proposals, mc_beta, manifest = distribution_inputs(args.lattice, args.scratch_root, args.manifest)
        if args.mc_root is not None:
            mc = args.mc_root
    analyze_distributions(paths, mc, args.output, args.lattice, tuple(args.targets or targets),
                          args.updates if args.updates is not None else updates, proposals, mc_beta,
                          args.bootstrap, args.seed, args.burn_in, args.block_size,
                          args.bin_width, args.max_bins, manifest, args.probability_floor)


if __name__ == "__main__":
    main()
