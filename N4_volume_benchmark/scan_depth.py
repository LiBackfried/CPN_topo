#!/usr/bin/env python3
"""Scan equal-length CP^3 stream prefixes at beta 0.7 and report target coverage."""

from __future__ import annotations

import argparse
import csv
import sys
from collections.abc import Sequence
from itertools import islice
from pathlib import Path

import numpy as np
from scipy.special import logsumexp

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from analyze_nested_sampling import evaluate_at_beta
from utils.cpn_io import discover_runs, read_config
from utils.nest_sampl import NestedSamplingStream, bootstrap_nested_sampling, combine_streams

SOURCE_BETA = 0.7
N = 4
STATISTICS = ("mean_action_density", "xi_L_squared", "chi_topological", "log_Z_ratio")
OBSERVABLES = ("action_density", "g0", "gk", "q_u", "q_z", "q_plaq")


def load_segment(path: Path, config: dict) -> np.ndarray:
    updates = int(config["num_ns_meas"][0]) - 1
    cooling = int(config["num_cool_step"][0])
    spacing = int(config["meas_cool_every"][0])
    general = np.loadtxt(path / "dati.dat", ndmin=2)
    with (path / "topo.dat").open() as file:
        # Only keep the final cooling row from each dead point's block.
        rows = (line for line in file if not line.startswith("#"))
        topology = np.loadtxt(islice(rows, cooling // spacing, None, cooling // spacing + 1),
                              usecols=(0, 1, 2, 3, 4), ndmin=2)
    iterations = np.loadtxt(path / "acceptance_rate.dat", usecols=0, ndmin=1, dtype=int)
    if (len(general) != updates + 1 or len(topology) != updates + 1
            or not np.array_equal(iterations, np.arange(1, updates + 1))
            or not np.array_equal(general[:, 0], topology[:, 0])
            or not np.all(topology[:, 1] == cooling)):
        raise ValueError(f"Incomplete or misaligned NS segment in {path}")
    return np.column_stack((general[:, 1:4], topology[:, 2:5]))


def load_chain(path: Path) -> tuple[dict, np.ndarray]:
    paths = []
    while True:
        if path in paths:
            raise ValueError(f"Cyclic continuation history in {path}")
        paths.append(path)
        parent = path / "parent_run"
        if not parent.exists():
            break
        path = (path / parent.read_text().strip()).resolve()

    segments = []
    settings = None
    for path in reversed(paths):
        config = read_config(path / "input.conf")
        expected_start, expected_rng = (2, 1) if segments else (1, 0)
        if (int(config["start"][0]), int(config["rng_start"][0])) != (expected_start, expected_rng):
            raise ValueError(f"Wrong start or RNG flags for segment {path}")
        if "Theory: 2d CP^{N-1} model with N = 4\n" not in (path / "log.dat").read_text():
            raise ValueError(f"Expected a completed N=4 simulation in {path}")
        comparable = {key: value for key, value in config.items()
                      if key not in {"start", "rng_start", "num_ns_meas"}}
        if settings is not None and comparable != settings:
            raise ValueError(f"Settings changed within continuation history at {path}")
        settings = comparable
        data = load_segment(path, config)
        if segments:
            if not np.allclose(segments[-1][-1], data[0], rtol=1e-10, atol=1e-10):
                raise ValueError(f"Continuation does not repeat the parent's final measurement in {path}")
            data = data[1:]
        segments.append(data)

    data = np.concatenate(segments)
    if not np.all(np.isfinite(data)) or np.any(np.diff(data[:, 0]) > 1e-12):
        raise ValueError(f"Non-finite measurements or increasing action in chain from {paths[0]}")
    return settings, data


def common_prefix(chains: Sequence[np.ndarray], updates: int, n_live: int) -> list[NestedSamplingStream]:
    cutoff = max(chain[updates, 0] for chain in chains)
    streams = []
    for index, chain in enumerate(chains):
        # Below this common cutoff at least one truncated stream is absent.
        prefix = chain[:updates + 1]
        prefix = prefix[prefix[:, 0] > cutoff]
        count = len(prefix)
        if count == 0:
            raise ValueError(f"No common energy support at {updates} updates; use a longer prefix")
        observables = dict(zip(OBSERVABLES, prefix.T))
        observables["energy"] = 2 * observables["action_density"]
        observables["stream_index"] = np.full(count, index)
        streams.append(NestedSamplingStream(observables["energy"], observables, n_live))
    return streams


def target_diagnostics(data, lattice: int, beta: float, n_streams: int) -> dict:
    target, statistics = evaluate_at_beta(data, lattice, SOURCE_BETA, beta, N)
    weights = target.weight
    owner = data.observables["stream_index"].astype(int)
    stream_mass = np.bincount(owner, weights=weights, minlength=n_streams)
    q99 = np.searchsorted(target.log_z_curve, np.log(0.99))
    log_x = data.log_x[-1]
    # For theta=0, H>=0 and exp[-(beta-beta0)*H]<=1. The bound is conditional
    # on the NS estimate of X and can remain loose after apparent convergence.
    log_missing_fraction_bound = log_x - np.logaddexp(log_x, target.log_z)
    return {
        "target_beta": beta,
        "common_points": len(weights),
        "common_epsilon_edge": data.observables["action_density"][-1],
        "minus_log_x": -log_x,
        "q99_points_per_stream": (q99 + 1) / n_streams,
        "q99_epsilon": data.observables["action_density"][q99],
        "last_tenth_target_mass": weights[-((len(weights) + 9) // 10):].sum(),
        "log_missing_target_fraction_bound": log_missing_fraction_bound,
        "quadrature_ess": statistics["quadrature_effective_sample_size"],
        "stream_weight_ess": 1 / np.sum(stream_mass ** 2),
        "max_stream_weight": max(stream_mass),
        "nonzero_Q_weight": weights[np.abs(data.observables["q_u"]) >= 0.5].sum(),
        **{key: statistics[key] for key in STATISTICS},
    }


def scan(chains: Sequence[np.ndarray], lattice: int, n_live: int, args) -> list[dict]:
    available = min(len(chain) - 1 for chain in chains)
    depths = sorted(set(args.updates or []) | {available})
    if depths[0] < 1 or depths[-1] > available:
        raise ValueError(f"Prefix lengths must be between 1 and {available} updates")

    def statistic(data):
        values = {}
        for beta in args.targets:
            _, estimates = evaluate_at_beta(data, lattice, SOURCE_BETA, beta, N)
            values.update({f"{beta}/{key}": estimates[key] for key in STATISTICS})
        return values

    rows, draws = [], []
    for updates in depths:
        streams = common_prefix(chains, updates, n_live)
        merged = combine_streams(streams)
        rows.append([
            {"L": lattice, "chains": len(chains), "updates": updates,
             **target_diagnostics(merged, lattice, beta, len(chains))}
            for beta in args.targets
        ])
        if args.bootstrap:
            # The same seed draws the same chain indices for every prefix.
            _, _, samples = bootstrap_nested_sampling(streams, statistic, args.bootstrap, args.seed)
            draws.append(samples)

    for depth, group in enumerate(rows):
        for row, reference in zip(group, rows[-1]):
            for key in STATISTICS:
                row[f"{key}_shift_from_deepest"] = row[key] - reference[key]
                if args.bootstrap:
                    sample_key = f"{row['target_beta']}/{key}"
                    values, full = draws[depth][sample_key], draws[-1][sample_key]
                    row[f"{key}_bootstrap_se"] = np.std(values, ddof=1)
                    row[f"{key}_paired_abs_shift_p95"] = np.quantile(np.abs(values - full), 0.95)
    return [row for group in rows for row in group]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_roots", type=Path, nargs="+", help="Leaf job roots or independent run directories")
    parser.add_argument("--updates", type=int, nargs="+", help="Prefix lengths, in addition to the deepest shared length")
    parser.add_argument("--targets", type=float, nargs="+", default=[0.8, 0.9, 1.0])
    parser.add_argument("--bootstrap", type=int, default=0, help="Paired whole-stream replicates (0 disables)")
    parser.add_argument("--seed", type=int, default=20261106)
    args = parser.parse_args()
    if args.bootstrap < 0 or args.bootstrap == 1 or args.seed < 0:
        parser.error("Use 0 or at least 2 bootstrap replicates and a nonnegative seed")
    if any(not np.isfinite(beta) or beta < SOURCE_BETA for beta in args.targets):
        parser.error("This low-energy coverage scan requires finite target betas >= 0.7")
    if len(set(args.targets)) != len(args.targets):
        parser.error("Specify each target beta only once")

    configs, chains = zip(*(load_chain(path) for path in discover_runs(args.run_roots)))
    if len(chains) < 2:
        parser.error("At least two independently seeded chains are required")
    seeds = {int(config["rng_seed"][0]) for config in configs}
    if len(seeds) != len(chains) or min(seeds) < 1:
        parser.error("Use one leaf per independent positive seed; do not pass its ancestors as other inputs")
    lattice, other_extent = map(int, configs[0]["size"])
    if lattice != other_extent:
        parser.error("Expected a square lattice")
    for config in configs:
        if (float(config["beta"][0]), float(config["theta"][0])) != (SOURCE_BETA, 0.0):
            parser.error("Expected source beta 0.7 and theta 0")
        if {k: v for k, v in config.items() if k != "rng_seed"} != {
                k: v for k, v in configs[0].items() if k != "rng_seed"}:
            parser.error("Compare ensembles with different settings in separate scans")

    rows = scan(chains, lattice, int(configs[0]["num_live_pts"][0]), args)
    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)


if __name__ == "__main__":
    main()
