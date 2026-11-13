#!/usr/bin/env python3
"""Plot regular CPN MCMC histories and binning diagnostics for a job directory."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from utils.mcmc import OBSERVABLES, MCMCChain, binning_analysis, load_ensemble


LABELS = (r"$\langle\epsilon\rangle$", r"$\langle Q_U\rangle$", r"$\langle Q_U^2\rangle$",
          r"$\chi_{\mathrm{top}}$", r"$\xi_L^2$")


def plot_histories(chains: list[MCMCChain], retained: list[MCMCChain], burn_in: int,
                   output: Path, title: str) -> None:
    fig, axes = plt.subplots(len(chains), 2, squeeze=False, sharex=True,
                             figsize=(11, 2.6 * len(chains)), constrained_layout=True)
    for chain, kept, (action_ax, charge_ax) in zip(chains, retained, axes):
        color = "C0"
        action_ax.plot(chain.steps, chain.action_density, color=color, linewidth=0.7)
        charge_ax.step(chain.steps, chain.q_u, where="post", color=color, linewidth=0.7)
        sectors = np.rint(kept.q_u)
        changes = np.count_nonzero(np.diff(sectors))
        action_ax.set_title(chain.path.name)
        charge_ax.set_title(f"{chain.path.name} · {changes:,} sector changes after burn-in")
        action_ax.set_ylabel(r"Action density $\epsilon$")
        charge_ax.set_ylabel(r"Geometric charge $Q_U$")
        for ax in (action_ax, charge_ax):
            if burn_in >= chain.steps[0]:
                ax.axvspan(chain.steps[0], burn_in, color="0.8", alpha=0.5)
                ax.axvline(burn_in, color="0.35", linestyle="--", linewidth=0.8)
    for ax in axes[-1]:
        ax.set_xlabel("MC step")
    fig.suptitle(f"{title} · cooling step {chains[0].cooling_step} for topology")
    fig.savefig(output / "histories.png", dpi=150)
    plt.close(fig)


def plot_action_histogram(chains: list[MCMCChain], output: Path, title: str) -> None:
    fig, ax = plt.subplots(figsize=(7, 4.5), constrained_layout=True)
    bins = np.histogram_bin_edges(np.concatenate([chain.action_density for chain in chains]), bins=60)
    for chain in chains:
        ax.hist(chain.action_density, bins=bins, density=True, histtype="step", label=chain.path.name)
    ax.set(xlabel=r"Action density $\epsilon$", ylabel="Probability density", title=title)
    ax.legend()
    fig.savefig(output / "action_histogram.png", dpi=150)
    plt.close(fig)


def write_binning(chains: list[MCMCChain], min_blocks: int, output: Path, title: str) -> None:
    groups = [(chain.path.name, [chain]) for chain in chains]
    if len(chains) > 1:
        groups.append(("pooled", chains))
    stride = chains[0].meas_every
    fig, axes = plt.subplots(2, 3, figsize=(12, 6.5), constrained_layout=True)
    axes = axes.ravel()
    with (output / "binning.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(("chain", "block_size_measurements", "block_size_mc_steps", "n_blocks",
                         "observable", "estimate", "standard_error"))
        for name, group in groups:
            results = binning_analysis(group, min_blocks)
            pooled = name == "pooled"
            x = [result.block_size * stride for result in results]
            for i, (observable, label) in enumerate(zip(OBSERVABLES, LABELS)):
                errors = [result.standard_error[i] for result in results]
                axes[i].plot(x, errors, "o-", markersize=3, label=name,
                             color="black" if pooled else None, linewidth=2 if pooled else 1)
                axes[i].set(xscale="log", xlabel="Bin length (MC steps)", ylabel="Standard error",
                            title=label)
                for result, mc_steps in zip(results, x):
                    writer.writerow((name, result.block_size, mc_steps, result.n_blocks, observable,
                                     result.estimate[i], result.standard_error[i]))
    handles, labels = axes[0].get_legend_handles_labels()
    axes[-1].axis("off")
    axes[-1].legend(handles, labels, loc="center", frameon=False)
    fig.suptitle(title)
    fig.savefig(output / "binning.png", dpi=150)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path, help="job directory containing run_0, run_1, ...")
    parser.add_argument("-o", "--output", type=Path, help="default: mcmc_analysis inside the job directory")
    parser.add_argument("--burn-in", type=int, default=0, metavar="MC_STEPS",
                        help="discard observations at or before this MC step (default: 0)")
    parser.add_argument("--cooling-step", type=int, help="default: last measured cooling step")
    parser.add_argument("--min-blocks", type=int, default=16, help="minimum bins per chain (default: 16)")
    args = parser.parse_args()
    parent = args.parent.expanduser().resolve()
    try:
        chains = load_ensemble(parent, args.cooling_step)
        retained = [chain.after_burn_in(args.burn_in) for chain in chains]
        if args.min_blocks < 2 or min(len(chain.steps) for chain in retained) < args.min_blocks:
            raise ValueError("min-blocks must be at least two and no larger than the shortest retained chain")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))

    output = args.output.expanduser().resolve() if args.output else parent / "mcmc_analysis"
    output.mkdir(parents=True, exist_ok=True)
    first = chains[0]
    title = f"{first.size[0]} × {first.size[1]} MCMC · β={first.beta:g} · θ={first.theta:g}"
    plot_histories(chains, retained, args.burn_in, output, title)
    plot_action_histogram(retained, output, title)
    write_binning(retained, args.min_blocks, output, title)
    for chain in retained:
        sectors = np.rint(chain.q_u)
        changes = np.count_nonzero(np.diff(sectors))
        print(f"{chain.path.name}: {len(chain.steps):,} retained measurements, "
              f"{len(np.unique(sectors))} visited Q_U sectors, {changes:,} sector changes")
    print(f"Wrote MCMC diagnostics to {output}")


if __name__ == "__main__":
    main()
