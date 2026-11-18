#!/usr/bin/env python3
"""Compare reweighted NS and direct MCMC on shared action-density bins."""

from __future__ import annotations

import argparse
import csv
import sys
from functools import partial
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.scan_depth import N, SOURCE_BETA, common_prefix, load_ns_ensemble
from utils.cpn_io import read_config
from utils.mcmc import load_ensemble
from utils.nest_sampl import bootstrap_nested_sampling, reweight_beta


OBSERVABLES = ("G0", "Gk")


def bin_totals(action, correlators, edges, weights=None):
    """Return mass and weighted correlator sums, including both tails."""
    index = np.searchsorted(edges, action, side="right")
    if weights is None:
        weights = np.ones_like(action, dtype=float)
    columns = [weights, *(weights * correlator for correlator in correlators)]
    return np.column_stack([np.bincount(index, weights=column, minlength=len(edges) + 1)
                            for column in columns])


def mcmc_block_totals(chains, block_size, edges):
    blocks = []
    for chain in chains:
        for start in range(0, len(chain.steps) - block_size + 1, block_size):
            take = slice(start, start + block_size)
            blocks.append(bin_totals(chain.action_density[take],
                                     (chain.g0[take], chain.gk[take]), edges))
    return np.stack(blocks)


def comparison(ns, mc):
    """Return bin estimates and a symmetric decomposition of NS minus MCMC.

    Leading array dimensions may index resamples. Bin masses are fractions
    of the whole ensemble, while the decomposition first renormalizes each
    ensemble to the common range. Add the effect of excluding the tails to
    recover the full-ensemble difference.
    """
    ns, mc = np.broadcast_arrays(ns, mc)
    ns_mass, mc_mass = ns[..., 1:-1, 0], mc[..., 1:-1, 0]
    if np.any(ns_mass <= 0) or np.any(mc_mass <= 0):
        raise ValueError("Empty comparison bin in an estimate or resample. Use fewer bins or a narrower range.")
    ns_mean = ns[..., 1:-1, 1:] / ns_mass[..., None]
    mc_mean = mc[..., 1:-1, 1:] / mc_mass[..., None]
    ns_total, mc_total = ns.sum(axis=-2), mc.sum(axis=-2)
    ns_fraction = ns_mass / ns_total[..., 0, None]
    mc_fraction = mc_mass / mc_total[..., 0, None]
    ns_common, mc_common = ns_fraction.sum(axis=-1), mc_fraction.sum(axis=-1)
    p = ns_fraction[..., None] / ns_common[..., None, None]
    q = mc_fraction[..., None] / mc_common[..., None, None]
    delta = ns_mean - mc_mean
    within_bin = np.sum((p + q) / 2 * delta, axis=-2)
    bin_weight = np.sum((p - q) * (ns_mean + mc_mean) / 2, axis=-2)
    ns_full = ns_total[..., 1:] / ns_total[..., 0, None]
    mc_full = mc_total[..., 1:] / mc_total[..., 0, None]
    full_difference = ns_full - mc_full
    bins = {"ns_mass": ns_fraction, "mcmc_mass": mc_fraction}
    for i, name in enumerate(OBSERVABLES):
        bins[f"ns_{name}"] = ns_mean[..., i]
        bins[f"mcmc_{name}"] = mc_mean[..., i]
        bins[f"delta_{name}"] = delta[..., i]
    summary = {
        "ns_mean": ns_full, "mcmc_mean": mc_full, "full_difference": full_difference,
        "common_range_difference": within_bin + bin_weight,
        "within_bin": within_bin, "bin_weight": bin_weight,
        "outside_range_effect": full_difference - within_bin - bin_weight,
        "ns_mass_in_range": np.broadcast_to(ns_common[..., None], ns_full.shape),
        "mcmc_mass_in_range": np.broadcast_to(mc_common[..., None], mc_full.shape),
    }
    return bins, summary


def aggregate_ns(data, edges, lattice, beta):
    target, _, _ = reweight_beta(data, SOURCE_BETA, beta, N, lattice**2)
    obs = target.observables
    totals = bin_totals(obs["action_density"], (obs["g0"], obs["gk"]), edges, target.weight)
    return {str(i): value for i, value in enumerate(totals.ravel())}


def independent_errors(ns_draws, mc_draws):
    """Combine NS bootstrap and MCMC delete-block jackknife variances."""
    return {key: np.hypot(ns_draws[key].std(axis=0, ddof=1),
                          np.sqrt(len(mc_draws[key]) - 1) * mc_draws[key].std(axis=0))
            for key in ns_draws}


def write_csv(path, leading_columns, estimates, errors):
    columns = dict(leading_columns)
    for key, estimate in estimates.items():
        columns[key] = estimate
        columns[f"{key}_se"] = errors[key]
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(columns)
        writer.writerows(zip(*columns.values()))


def plot_comparison(path, edges, estimates, errors, title):
    center = (edges[:-1] + edges[1:]) / 2
    width = np.diff(edges)
    fig, axes = plt.subplots(3, 1, sharex=True, figsize=(8, 8), constrained_layout=True)
    for key, label, color in (("mcmc_mass", "Direct MCMC", "0.2"), ("ns_mass", "Reweighted NS", "C0")):
        axes[0].step(np.repeat(edges, 2)[1:-1], np.repeat(estimates[key] / width, 2),
                     color=color, label=label)
    axes[0].set_ylabel("Action probability density")
    axes[0].legend(frameon=False)
    for ax, key, label in zip(axes[1:], ("delta_G0", "delta_Gk"), (r"$G_0$", r"$G_k$")):
        ax.axhline(0, color="0.55", linewidth=1, linestyle="--")
        ax.errorbar(center, estimates[key], xerr=width / 2, yerr=errors[key],
                    fmt="o", markersize=4, capsize=2, color="C0")
        ax.set_ylabel(f"{label}  NS − MCMC")
    axes[-1].set_xlabel(r"Action density $\epsilon$")
    fig.suptitle(title)
    fig.savefig(path, dpi=160)
    plt.close(fig)


def run(args):
    config, data = load_ns_ensemble(args.ns)
    lattice = int(config["size"][0])
    depth = min(len(chain) - 1 for chain in data)
    if not 1 <= args.updates <= depth:
        raise ValueError(f"NS depth must be between 1 and {depth} updates")
    chains = [c.after_burn_in(args.burn_in) for c in load_ensemble(args.mcmc)]
    for chain in chains:
        if (chain.size, chain.beta, chain.theta) != ((lattice, lattice), args.beta, 0.0):
            raise ValueError(f"MCMC size, beta, or theta does not match the NS target in {chain.path}")
        mcmc_config = read_config(chain.path / "input.conf")
        log = chain.path / mcmc_config.get("log_file", ["log.dat"])[0]
        if f"Theory: 2d CP^{{N-1}} model with N = {N}" not in log.read_text().splitlines():
            raise ValueError(f"expected a completed N={N} MCMC run in {chain.path}")
        if len(chain.steps) < 2 * args.block_size:
            raise ValueError(f"at least two full MCMC blocks per chain are required in {chain.path}")

    actions = np.concatenate([c.action_density[:len(c.steps) // args.block_size * args.block_size]
                              for c in chains])
    edges = np.quantile(actions, np.linspace(args.tail, 1 - args.tail, args.bins + 1))
    if np.any(np.diff(edges) <= 0):
        raise ValueError("Repeated MCMC quantile edges. Use fewer bins.")
    cutoff = max(chain[args.updates, 0] for chain in data)
    if cutoff >= edges[0]:
        raise ValueError("The NS common cutoff reaches into the comparison range. Increase NS depth or trim the tails.")

    blocks = mcmc_block_totals(chains, args.block_size, edges)
    mc_total = blocks.sum(axis=0)
    streams = common_prefix(data, args.updates, int(config["num_live_pts"][0]))
    shape = (len(edges) + 1, 3)
    statistic = partial(aggregate_ns, edges=edges, lattice=lattice, beta=args.beta)
    values, _, draws = bootstrap_nested_sampling(streams, statistic, args.bootstrap, args.seed)
    ns_total = np.array(list(values.values())).reshape(shape)
    ns_draws = np.column_stack(list(draws.values())).reshape(args.bootstrap, *shape)

    bins, summary = comparison(ns_total, mc_total)
    ns_bins, ns_summary = comparison(ns_draws, mc_total)
    mc_bins, mc_summary = comparison(ns_total, mc_total - blocks)
    bin_errors = independent_errors(ns_bins, mc_bins)
    args.output.mkdir(parents=True, exist_ok=True)
    write_csv(args.output / "bins.csv", {"epsilon_lo": edges[:-1], "epsilon_hi": edges[1:]},
              bins, bin_errors)
    write_csv(args.output / "summary.csv", {"observable": OBSERVABLES},
              summary, independent_errors(ns_summary, mc_summary))
    proposals = int(config["num_single_site_stoc_upd"][0])
    title = f"L={lattice}, β={args.beta:g} · {len(streams)} NS chains, {proposals:,} proposals/update"
    plot_comparison(args.output / "comparison.png", edges, bins, bin_errors, title)
    print(f"Compared {len(streams)} NS chains at {args.updates:,} updates per chain "
          f"with {len(chains)} MCMC chains. Wrote {args.output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ns", nargs="+", required=True, type=Path, help="leaf jobs for one NS ensemble")
    parser.add_argument("--mcmc", required=True, type=Path, help="parent directory of the direct MCMC runs")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--updates", type=int, default=35000)
    parser.add_argument("--beta", type=float, default=1.0)
    parser.add_argument("--burn-in", type=int, default=20000, help="discard MCMC measurements through this MC step")
    parser.add_argument("--block-size", type=int, default=128, help="MCMC measurements per jackknife block")
    parser.add_argument("--bins", type=int, default=16, help="number of common bins set by MCMC quantiles")
    parser.add_argument("--tail", type=float, default=0.005, help="MCMC mass excluded on each end of the comparison")
    parser.add_argument("--bootstrap", type=int, default=200)
    parser.add_argument("--seed", type=int, default=20261106)
    args = parser.parse_args()
    if (args.bins < 2 or args.block_size < 1 or not 0 < args.tail < 0.5
            or args.bootstrap < 2 or args.seed < 0 or not np.isfinite(args.beta) or args.beta < SOURCE_BETA):
        parser.error("Require at least two bins and bootstrap draws, positive block size, 0 < tail < 0.5, "
                     "nonnegative seed, and finite target beta >= 0.7")
    try:
        run(args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
