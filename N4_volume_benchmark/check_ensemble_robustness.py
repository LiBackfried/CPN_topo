#!/usr/bin/env python3
"""Check action-bin/block robustness and independent-stream influence for CP^3."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from functools import partial
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from analyze_nested_sampling import evaluate_at_beta
from N4_volume_benchmark.compare_action_bins import (
    OBSERVABLES, bin_totals, comparison, independent_errors, mcmc_block_totals,
    plot_comparison, write_csv,
)
from N4_volume_benchmark.scan_depth import N, SOURCE_BETA, STATISTICS, common_prefix, load_ns_ensemble
from utils.cpn_io import discover_runs, read_config
from utils.mcmc import OBSERVABLES as MC_OBSERVABLES, binning_analysis, load_ensemble
from utils.nest_sampl import bootstrap_nested_sampling, combine_streams


def save_rows(path, rows):
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def statistic(data, *, edges, lattice, beta):
    target, values = evaluate_at_beta(data, lattice, SOURCE_BETA, beta, N)
    result = {key: values[key] for key in STATISTICS}
    for count, boundaries in edges.items():
        totals = bin_totals(target.observables["action_density"],
                            (target.observables["g0"], target.observables["gk"]),
                            boundaries, target.weight)
        result.update({f"bins{count}/{i}": value for i, value in enumerate(totals.ravel())})
    return result


def unpack(values, count):
    return np.stack([values[f"bins{count}/{i}"] for i in range((count + 2) * 3)],
                    axis=-1).reshape((*np.shape(values[f"bins{count}/0"]), count + 2, 3))


def delta_vector(bins):
    """One joint vector: all G0 bins followed by all Gk bins."""
    return np.concatenate([bins[f"delta_{name}"] for name in OBSERVABLES], axis=-1)


def block_bootstrap_totals(blocks, replicates, rng):
    """Resample complete, equal-sized blocks; each input block stays intact."""
    count = len(blocks)
    flat = blocks.reshape(count, -1)
    result = np.empty((replicates, flat.shape[1]))
    # Bound temporary memory independently of the number of MCMC measurements.
    for first in range(0, replicates, 32):
        last = min(first + 32, replicates)
        multiplicities = rng.multinomial(count, np.full(count, 1 / count), last - first)
        result[first:last] = multiplicities @ flat
    return result.reshape(replicates, *blocks.shape[1:])


def joint_diagnostics(delta, ns_draws, mc_jackknife, mc_bootstrap, rng):
    """Covariance and centered, correlation-preserving max-|z| diagnostic.

    The null is approximated by independent centered NS whole-stream draws
    and MCMC whole-block draws. This is a bootstrap diagnostic conditional on
    fixed action edges and adequate block lengths, not a physics validation.
    """
    covariance = (np.cov(ns_draws, rowvar=False, ddof=1)
                  + (len(mc_jackknife) - 1) * np.cov(mc_jackknife, rowvar=False, ddof=0))
    error = np.sqrt(np.diag(covariance))
    if not np.all(np.isfinite(covariance)) or np.any(error <= 0):
        raise ValueError("Joint diagnostic needs finite, positive errors in every bin")
    centered_ns = ns_draws - ns_draws.mean(axis=0)
    centered_mc = mc_bootstrap - mc_bootstrap.mean(axis=0)
    # Both inputs are residual vectors (NS minus MC): their centered variations
    # already carry the appropriate signs for the two independent methods.
    null = centered_ns[rng.integers(0, len(ns_draws), len(centered_mc))] + centered_mc
    null_max = np.max(np.abs(null / error), axis=1)
    observed = float(np.max(np.abs(delta / error)))
    critical = float(np.quantile(null_max, 0.95))
    result = {
        "max_abs_z": observed,
        "joint_bootstrap_p": float((1 + np.count_nonzero(null_max >= observed)) / (len(null_max) + 1)),
        "simultaneous_95_critical_z": critical,
        "ns_bootstrap_replicates": len(ns_draws), "joint_replicates": len(null_max),
        "p_resolution": 1 / (len(null_max) + 1),
        "scope": "Both correlators and all bins in this configuration; fixed MCMC-derived edges.",
        "caveat": "Approximate centered bootstrap; requires independent NS streams and sufficiently long MCMC blocks. Grid rows are correlated; do not select the smallest p as a global test.",
    }
    return result, covariance, error


def write_comparison(output, boundaries, ns_total, ns_draws, blocks, joint_replicates, seed, title):
    output.mkdir(parents=True, exist_ok=False)
    mc_total = blocks.sum(axis=0)
    bins, summary = comparison(ns_total, mc_total)
    ns_bins, ns_summary = comparison(ns_draws, mc_total)
    mc_bins, mc_summary = comparison(ns_total, mc_total - blocks)
    errors = independent_errors(ns_bins, mc_bins)
    rng = np.random.default_rng(seed)
    mc_bootstrap, _ = comparison(ns_total, block_bootstrap_totals(blocks, joint_replicates, rng))
    joint, covariance, joint_error = joint_diagnostics(
        delta_vector(bins), delta_vector(ns_bins), delta_vector(mc_bins), delta_vector(mc_bootstrap), rng)
    write_csv(output / "bins.csv", {"epsilon_lo": boundaries[:-1], "epsilon_hi": boundaries[1:]}, bins, errors)
    write_csv(output / "summary.csv", {"observable": OBSERVABLES}, summary,
              independent_errors(ns_summary, mc_summary))
    count = len(boundaries) - 1
    labels = [f"{name}_bin{i + 1}" for name in OBSERVABLES for i in range(count)]
    save_rows(output / "covariance.csv", [dict(zip(["component", *labels], [label, *row]))
                                          for label, row in zip(labels, covariance)])
    residual = delta_vector(bins)
    radius = joint["simultaneous_95_critical_z"] * joint_error
    save_rows(output / "simultaneous_intervals.csv", [
        dict(component=label, delta=value, se=error, lower_95=value - halfwidth, upper_95=value + halfwidth)
        for label, value, error, halfwidth in zip(labels, residual, joint_error, radius)])
    (output / "joint.json").write_text(json.dumps(joint, indent=2) + "\n", encoding="utf-8")
    plot_comparison(output / "comparison.png", boundaries, bins, errors, title)
    return joint


def plot_stream_checks(output, rows, influence, baseline):
    keys = ("mean_action_density", "xi_L_squared", "chi_topological", "mean_G0", "mean_Gk")
    fig, axes = plt.subplots(2, 3, figsize=(13, 7), constrained_layout=True)
    for axis, key in zip(axes.flat, keys):
        selected = [row for row in rows if row["observable"] == key and row["subset"].startswith("leave_out_")]
        axis.axhline(0, color="0.5", linewidth=1)
        axis.plot([row["omitted_stream"] for row in selected], [row["shift_over_full_se"] for row in selected], "o-")
        axis.set(title=key, xlabel="Omitted stream (see streams.csv)", ylabel="Shift / full NS bootstrap SE")
    axes.flat[-1].axis("off")
    fig.suptitle("Leave-one-out influence (descriptive shifts, not significance tests)")
    fig.savefig(output / "leave_one_out_observables.png", dpi=160)
    plt.close(fig)
    fig, axes = plt.subplots(2, 1, figsize=(11, 7), constrained_layout=True)
    matrix = np.array([float(row["shift_over_full_se"] or 0) for row in influence]).reshape(12, 2, baseline)
    limit = max(float(np.max(np.abs(matrix))), 1e-12)
    for i, axis in enumerate(axes):
        mesh = axis.imshow(matrix[:, i], aspect="auto", origin="lower", cmap="RdBu_r", vmin=-limit, vmax=limit,
                           extent=(.5, baseline + .5, -.5, 11.5))
        axis.set(title=OBSERVABLES[i], xlabel="Action-bin number", ylabel="Omitted stream")
        axis.set_yticks(range(12))
        fig.colorbar(mesh, ax=axis, label="Shift / full NS bootstrap SE")
    fig.savefig(output / "leave_one_out_bins.png", dpi=160)
    plt.close(fig)


def run(args):
    if args.output.exists():
        raise ValueError(f"Refusing to overwrite existing output: {args.output}")
    groups = [discover_runs([root]) for root in args.ns]
    if len(groups) != 3 or any(len(group) != 4 for group in groups):
        raise ValueError("Pass three NS leaf job roots, each containing exactly four independent streams")
    paths = [path for group in groups for path in group]
    if len(set(paths)) != 12:
        raise ValueError("NS groups must be disjoint")
    config, data = load_ns_ensemble(paths)
    lattice, n_live = int(config["size"][0]), int(config["num_live_pts"][0])
    if not 1 <= args.updates <= min(len(chain) - 1 for chain in data):
        raise ValueError("Requested updates exceed available cumulative NS depth")
    chains = [chain.after_burn_in(args.burn_in) for chain in load_ensemble(args.mcmc)]
    for chain in chains:
        if (chain.size, chain.beta, chain.theta) != ((lattice, lattice), args.beta, 0.):
            raise ValueError(f"MCMC lattice/beta/theta mismatch: {chain.path}")
        cfg = read_config(chain.path / "input.conf")
        log = chain.path / cfg.get("log_file", ["log.dat"])[0]
        if f"Theory: 2d CP^{{N-1}} model with N = {N}" not in log.read_text().splitlines():
            raise ValueError(f"Expected N={N} MCMC log in {chain.path}")
        if len(chain.steps) < 16 * max(args.blocks):
            raise ValueError("Need at least 16 complete MCMC blocks per chain at every requested block size")
    # Match the original comparison's 128-block support, then freeze boundaries
    # across block sizes and stream subsets. Only incomplete MC tails vary.
    edge_block = min(args.blocks)
    actions = np.concatenate([c.action_density[:len(c.steps) // edge_block * edge_block] for c in chains])
    edges = {count: np.quantile(actions, np.linspace(args.tail, 1 - args.tail, count + 1))
             for count in args.bins}
    cutoff = max(chain[args.updates, 0] for chain in data)
    if any(np.any(np.diff(e) <= 0) or cutoff >= e[0] for e in edges.values()):
        raise ValueError("Repeated bin edges or insufficient NS depth for the comparison range")
    streams = common_prefix(data, args.updates, n_live)
    args.output.mkdir(parents=True)
    provenance = dict(L=lattice, beta=args.beta, source_beta=SOURCE_BETA, updates=args.updates,
                      burn_in_MC_steps=args.burn_in, block_sizes_measurements=args.blocks,
                      bin_counts=args.bins, bootstrap=args.bootstrap, joint_draws=args.joint_draws,
                      seed=args.seed, common_epsilon_cutoff=cutoff, live_points_per_stream=n_live,
                      ns_groups=[[str(path) for path in group] for group in groups],
                      mcmc=str(args.mcmc.resolve()), tail=args.tail,
                      edge_reference_block_size=edge_block,
                      bin_edges={str(key): value.tolist() for key, value in edges.items()})
    (args.output / "inputs.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    identities = [dict(stream=i, group=i // 4 + 1, path=str(path),
                       seed=int(read_config(path / "input.conf")["rng_seed"][0])) for i, path in enumerate(paths)]
    save_rows(args.output / "streams.csv", identities)
    stat = partial(statistic, edges=edges, lattice=lattice, beta=args.beta)
    print(f"L{lattice}: bootstrap full twelve-stream ensemble", flush=True)
    full, full_errors, draws = bootstrap_nested_sampling(streams, stat, args.bootstrap, args.seed)
    grid_dir = args.output / "step1"
    grid_dir.mkdir()
    grid = []
    for count in args.bins:
        for block in args.blocks:
            print(f"L{lattice}: {count} bins, MC block {block}", flush=True)
            blocks = mcmc_block_totals(chains, block, edges[count])
            joint = write_comparison(grid_dir / f"bins{count}_block{block}", edges[count],
                                     unpack(full, count), unpack(draws, count), blocks, args.joint_draws,
                                     args.seed + count * 10000 + block,
                                     f"L={lattice}, β={args.beta:g}, 12 streams · {count} bins, block {block}")
            grid.append(dict(bins=count, block_measurements=block, mcmc_blocks=len(blocks),
                             retained_measurements=len(blocks) * block,
                             **{key: joint[key] for key in ("max_abs_z", "joint_bootstrap_p", "simultaneous_95_critical_z")}))
    save_rows(grid_dir / "grid.csv", grid)

    step2 = args.output / "step2"
    step2.mkdir()
    baseline = args.baseline_bins
    boundaries = edges[baseline]
    blocks = mcmc_block_totals(chains, args.baseline_block, boundaries)
    mc_total = blocks.sum(axis=0)
    mc_reference = next(row for row in binning_analysis(chains) if row.block_size == args.baseline_block)
    mc_index = {key: index for index, key in enumerate(MC_OBSERVABLES)}
    rows = []

    def record(label, values, errors=None, omitted=None):
        for key in STATISTICS:
            shift = values[key] - full[key]
            index = mc_index.get(key)
            rows.append(dict(subset=label, omitted_stream="" if omitted is None else omitted,
                             observable=key, estimate=values[key], bootstrap_se="" if errors is None else errors[key],
                             shift_from_full=shift, shift_over_full_se=shift / full_errors[key] if full_errors[key] > 0 else "",
                             mcmc_mean="" if index is None else mc_reference.estimate[index],
                             mcmc_se="" if index is None else mc_reference.standard_error[index]))

    record("full12", full, full_errors)
    group_stat = partial(statistic, edges={baseline: boundaries}, lattice=lattice, beta=args.beta)
    group_estimates = []
    for group in range(3):
        print(f"L{lattice}: bootstrap independent group {group + 1}/3", flush=True)
        values, errors, group_draws = bootstrap_nested_sampling(
            streams[group * 4:(group + 1) * 4], group_stat, args.bootstrap, args.seed + group + 1)
        record(f"group{group + 1}", values, errors)
        group_estimates.append((values, errors, group_draws))
        write_comparison(step2 / f"group{group + 1}_bins{baseline}_block{args.baseline_block}", boundaries,
                         unpack(values, baseline), unpack(group_draws, baseline), blocks, args.joint_draws,
                         args.seed + 200000 + group,
                         f"L={lattice}, β={args.beta:g}, independent group {group + 1} (4 streams)")
    pairs = []
    for first in range(3):
        for second in range(first + 1, 3):
            a, a_error, a_draws = group_estimates[first]
            b, b_error, b_draws = group_estimates[second]
            components = [(key, a[key] - b[key], np.hypot(a_error[key], b_error[key])) for key in STATISTICS]
            a_bins, _ = comparison(unpack(a, baseline), mc_total)
            b_bins, _ = comparison(unpack(b, baseline), mc_total)
            a_samples, _ = comparison(unpack(a_draws, baseline), mc_total)
            b_samples, _ = comparison(unpack(b_draws, baseline), mc_total)
            for name in OBSERVABLES:
                key = f"ns_{name}"
                error = np.hypot(a_samples[key].std(axis=0, ddof=1), b_samples[key].std(axis=0, ddof=1))
                components.extend((f"{name}_bin{i + 1}", delta, se)
                                  for i, (delta, se) in enumerate(zip(a_bins[key] - b_bins[key], error)))
            pairs.extend(dict(group_a=first + 1, group_b=second + 1, component=key,
                              difference=delta, independent_group_se=se,
                              difference_over_se=delta / se if se > 0 else "") for key, delta, se in components)
    save_rows(step2 / "group_pairs.csv", pairs)
    full_bins, _ = comparison(unpack(full, baseline), mc_total)
    full_bin_draws, _ = comparison(unpack(draws, baseline), mc_total)
    influence = []
    for omitted in range(len(streams)):
        print(f"L{lattice}: leave out stream {omitted + 1}/12", flush=True)
        # Re-merge and recompute shrinkage with 11*nlive, using the same common
        # energy cutoff. Do not retain the twelve-stream quadrature weights.
        values = group_stat(combine_streams([stream for i, stream in enumerate(streams) if i != omitted]))
        record(f"leave_out_{omitted}", values, omitted=omitted)
        bins, _ = comparison(unpack(values, baseline), mc_total)
        for name in OBSERVABLES:
            se = full_bin_draws[f"ns_{name}"].std(axis=0, ddof=1)
            for index in range(baseline):
                shift = bins[f"ns_{name}"][index] - full_bins[f"ns_{name}"][index]
                influence.append(dict(omitted_stream=omitted, omitted_seed=identities[omitted]["seed"],
                                      observable=name, bin=index + 1, epsilon_lo=boundaries[index],
                                      epsilon_hi=boundaries[index + 1], estimate=bins[f"ns_{name}"][index],
                                      delta_mcmc=bins[f"delta_{name}"][index], shift_from_full=shift,
                                      full_ns_bootstrap_se=se[index],
                                      shift_over_full_se=shift / se[index] if se[index] > 0 else ""))
    save_rows(step2 / "observables.csv", rows)
    save_rows(step2 / "leave_one_out_bins.csv", influence)
    plot_stream_checks(step2, rows, influence, baseline)
    (args.output / "completed").touch()
    print(f"Completed both checks: {args.output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ns", nargs=3, type=Path, required=True)
    parser.add_argument("--mcmc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--updates", type=int, required=True)
    parser.add_argument("--beta", type=float, required=True)
    parser.add_argument("--bins", nargs="+", type=int, default=[8, 16, 32])
    parser.add_argument("--blocks", nargs="+", type=int, default=[128, 512, 1024])
    parser.add_argument("--baseline-bins", type=int, default=32)
    parser.add_argument("--baseline-block", type=int, default=512)
    parser.add_argument("--burn-in", type=int, default=20000)
    parser.add_argument("--tail", type=float, default=0.005)
    parser.add_argument("--bootstrap", type=int, default=200)
    parser.add_argument("--joint-draws", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=20261121)
    args = parser.parse_args()
    if (args.bootstrap < 2 or args.joint_draws < 2 or args.seed < 0 or args.burn_in < 0
            or not np.isfinite(args.beta) or args.beta < SOURCE_BETA or not 0 < args.tail < .5
            or any(count < 2 for count in args.bins) or any(block < 1 or block & (block - 1) for block in args.blocks)
            or len(set(args.bins)) != len(args.bins) or len(set(args.blocks)) != len(args.blocks)
            or args.baseline_bins not in args.bins or args.baseline_block not in args.blocks):
        parser.error("Require valid distinct bins, power-of-two blocks containing the baseline, >=2 draws, and beta >=0.7")
    try:
        run(args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
