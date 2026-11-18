#!/usr/bin/env python3
"""Evaluate an N=4 source-beta=0.7 ensemble over a beta grid."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.scan_depth import common_prefix, load_ns_ensemble, target_diagnostics
from N4_volume_benchmark.plot_beta_weights import BETAS, plot_single_run_weights
from analyze_nested_sampling import evaluate_at_beta
from utils.cpn_io import discover_runs
from utils.nest_sampl import bootstrap_nested_sampling, combine_streams


QUANTITIES = ("mean_action_density", "mean_G0", "mean_Gk", "mean_Q_U", "mean_Q_U_squared",
              "mean_Q_z", "mean_Q_plaquette", "mean_energy", "mean_extensive_energy",
              "mean_symanzik_action", "chi_topological", "xi_L_squared", "xi_L",
              "xi_L_over_L", "log_Z_ratio")


def beta_quantities(data, lattice, beta):
    _, estimates = evaluate_at_beta(data, lattice, 0.7, beta, 4)
    estimates["xi_L_over_L"] = estimates["xi_L"] / lattice
    return {key: estimates[key] for key in QUANTITIES}


def select_runs(paths, max_streams=None, selection_seed=20261118):
    """Choose paths without replacement before inspecting their measurements."""
    paths = sorted(paths, key=lambda path: path.as_posix())
    if selection_seed < 0:
        raise ValueError("stream selection seed must be nonnegative")
    if max_streams is None:
        return paths
    if max_streams < 2 or max_streams > len(paths):
        raise ValueError(f"stream count must be between 2 and {len(paths)}")
    indices = np.sort(np.random.default_rng(selection_seed).choice(
        len(paths), size=max_streams, replace=False))
    return [paths[index] for index in indices]


def analyze(roots, bootstrap, seed, output, expected_lattice=None, expected_stoc=None,
            expected_chains=None, max_streams=None, selection_seed=20261118,
            expected_available_chains=None):
    candidates = discover_runs(roots)
    if expected_available_chains is not None and len(candidates) != expected_available_chains:
        raise ValueError(f"expected {expected_available_chains} available chains, found {len(candidates)}")
    selected = select_runs(candidates, max_streams, selection_seed)
    output.mkdir(parents=True, exist_ok=True)
    # Save provenance before expensive I/O/bootstrap, including for a timed-out job.
    (output / "selected_runs.txt").write_text("\n".join(map(str, selected)) + "\n", encoding="utf-8")
    print(f"Loading {len(selected)} of {len(candidates)} candidate streams", flush=True)
    config, chains = load_ns_ensemble(selected)
    lattice = int(config["size"][0])
    stoc = int(config["num_single_site_stoc_upd"][0])
    if expected_lattice is not None and lattice != expected_lattice:
        raise ValueError(f"expected L={expected_lattice}, found L={lattice}")
    if expected_stoc is not None and stoc != expected_stoc:
        raise ValueError(f"expected {expected_stoc} stochastic proposals, found {stoc}")
    if expected_chains is not None and len(chains) != expected_chains:
        raise ValueError(f"expected {expected_chains} independent chains, found {len(chains)}")
    # Use one full, deterministically selected stream, with its own live count.
    # This diagnostic is separate from the merged common-support estimator.
    plot_single_run_weights(chains[0][:, 0], lattice, int(config["num_live_pts"][0]), output,
                            run=selected[0], rng_seed=int(config["rng_seed"][0]))
    depth = min(len(chain) - 1 for chain in chains)
    streams = common_prefix(chains, depth, int(config["num_live_pts"][0]))

    def statistic(data):
        return {f"{beta}/{key}": value for beta in BETAS
                for key, value in beta_quantities(data, lattice, beta).items()}

    estimates, errors, samples = bootstrap_nested_sampling(streams, statistic, bootstrap, seed)
    # Release replicate arrays after retaining finite fractions for nonlinear observables.
    finite = {key: float(np.isfinite(value).mean()) for key, value in samples.items()}
    del samples
    merged = combine_streams(streams)
    rows = []
    for beta in BETAS:
        row = {"L": lattice, "chains": len(chains), "updates": depth, "stochastic_proposals": stoc,
               **target_diagnostics(merged, lattice, beta, len(chains))}
        for key in QUANTITIES:
            row[key] = estimates[f"{beta}/{key}"]
            row[f"{key}_bootstrap_se"] = errors[f"{beta}/{key}"]
            row[f"{key}_bootstrap_finite_fraction"] = finite[f"{beta}/{key}"]
        rows.append(row)
    output.mkdir(parents=True, exist_ok=True)
    temporary = output / "beta_scan.csv.tmp"
    with temporary.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(output / "beta_scan.csv")
    (output / "inputs.json").write_text(json.dumps({
        "runs": [str(p) for p in selected], "available_chains": len(candidates),
        "max_streams": max_streams, "stream_selection_seed": selection_seed, "config": config,
        "bootstrap": bootstrap, "seed": seed, "depth": depth, "betas": BETAS,
    }, indent=2), encoding="utf-8")
    print(f"Wrote L={lattice} beta scan from {len(chains)} streams at {depth} updates to {output}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("roots", nargs="+", type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--bootstrap", type=int, default=200)
    p.add_argument("--seed", type=int, default=20261118)
    p.add_argument("--expected-lattice", type=int)
    p.add_argument("--expected-stoc", type=int)
    p.add_argument("--expected-chains", type=int)
    p.add_argument("--expected-available-chains", type=int)
    p.add_argument("--max-streams", type=int, help="Select this many streams before loading measurements")
    p.add_argument("--stream-selection-seed", type=int, default=20261118)
    args = p.parse_args()
    if args.bootstrap < 2 or args.seed < 0:
        p.error("require at least two bootstrap replicates and nonnegative seed")
    try:
        analyze(args.roots, args.bootstrap, args.seed, args.output,
                args.expected_lattice, args.expected_stoc, args.expected_chains,
                args.max_streams, args.stream_selection_seed, args.expected_available_chains)
    except (ValueError, OSError) as exc:
        p.error(str(exc))


if __name__ == "__main__":
    main()
