#!/usr/bin/env python3
"""Analyze and stream-bootstrap CP(N-1) nested-sampling runs.

Each positional input may be a run directory or a parent whose immediate
``run*`` children contain ``dati.dat``, ``topo.dat``, and ``input.conf``.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from utils.nest_sampl import CombinedNestedSampling, NestedSamplingStream
from utils.nest_sampl import bootstrap_nested_sampling, combine_streams, reweight_beta


def arguments() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("run_roots", nargs="+", type=Path)
    p.add_argument("-o", "--output", required=True, type=Path)
    p.add_argument("--bootstrap", type=int, default=1000)
    p.add_argument("--seed", type=int)
    p.add_argument("--action-prefactor", type=float, default=2.0,
                   help="energy = prefactor * dati.dat[:,1] (default: 2)")
    p.add_argument("--cpn-n", type=int, metavar="N",
                   help="compile-time CP(N-1) value; required for beta reweighting")
    p.add_argument("--target-beta", type=float,
                   help="reweight only beta to this value, keeping theta fixed")
    p.add_argument("--cooling-step", type=int, help="default: final cooling step")
    p.add_argument("--no-bootstrap", action="store_true")
    p.add_argument("--save-bootstrap-samples", action="store_true",
                   help="write every bootstrap replicate to bootstrap_samples.csv")
    return p.parse_args()


def read_config(path: Path) -> dict[str, list[str]]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("#", 1)[0].split()
        if fields:
            result[fields[0]] = fields[1:]
    return result


def discover_runs(roots: list[Path]) -> list[Path]:
    runs = []
    for root in roots:
        root = root.expanduser().resolve()
        if (root / "dati.dat").is_file():
            found = [root]
        else:
            found = [p for p in root.iterdir()
                     if p.is_dir() and re.fullmatch(r"run_?\d+", p.name)]
            found.sort(key=lambda p: int(re.search(r"\d+$", p.name).group()))
        if not found:
            raise FileNotFoundError(f"no run directories found under {root}")
        runs.extend(found)
    return list(dict.fromkeys(runs))


def table(path: Path) -> np.ndarray:
    data = np.loadtxt(path, comments="#", ndmin=2)
    if not np.all(np.isfinite(data)):
        raise ValueError(f"non-finite data in {path}")
    return data


def load_run(path: Path, prefactor: float, requested_cooling: int | None
             ) -> tuple[NestedSamplingStream, dict[str, Any]]:
    config = read_config(path / "input.conf")
    size = tuple(map(int, config["size"]))
    n_live = int(config["num_live_pts"][0])
    cool_every = int(config["meas_cool_every"][0])
    max_cool = int(config["num_cool_step"][0])
    cooling = max_cool if requested_cooling is None else requested_cooling
    if cooling < 0 or cooling > max_cool or cooling % cool_every:
        raise ValueError(f"cooling step {cooling} is unavailable in {path}")

    general, topology = table(path / "dati.dat"), table(path / "topo.dat")
    if general.shape[1] < 4 or topology.shape[1] < 5:
        raise ValueError(f"unexpected column count in {path}")
    block_size = max_cool // cool_every + 1
    count = min(len(general), len(topology) // block_size)
    acceptance = path / "acceptance_rate.dat"
    if acceptance.is_file():
        count = min(count, len(table(acceptance)))
    if count == 0:
        raise ValueError(f"no complete measurements in {path}")
    general = general[:count]
    topo = topology[:count * block_size].reshape(count, block_size, -1)[:, cooling // cool_every]
    energy = prefactor * general[:, 1]
    observables = {"energy": energy, "action_density": general[:, 1],
                   "g0": general[:, 2], "gk": general[:, 3],
                   "q_u": topo[:, 2], "q_z": topo[:, 3], "q_plaq": topo[:, 4]}
    stream = NestedSamplingStream(energy, observables, n_live, str(path))
    info = {"path": str(path), "size": size, "n_live": n_live,
            "n_measurements": count, "cooling_step": cooling,
            "beta": float(config.get("beta", ["nan"])[0]),
            "theta": float(config.get("theta", ["0.0"])[0])}
    return stream, info


def quantities(data: CombinedNestedSampling, lattice_size: int,
               cpn_n: int | None = None, beta: float | None = None
               ) -> dict[str, float]:
    g0, gk = data.mean("g0"), data.mean("gk")
    xi2 = (g0 / gk - 1.0) / (4.0 * np.sin(np.pi / lattice_size) ** 2)
    q_values = data.observables["q_u"]
    q, q2 = data.mean("q_u"), data.weighted_sum(q_values ** 2)
    q_variance = data.variance("q_u", mean=q)
    action_density = data.mean("action_density")
    result = {"mean_action_density": action_density,
              "mean_energy": data.mean("energy"), "mean_G0": g0, "mean_Gk": gk,
              "xi_L_squared": xi2, "xi_L": np.sqrt(xi2) if xi2 >= 0 else np.nan,
              "mean_Q_U": q, "mean_Q_U_squared": q2,
              "chi_topological": q_variance / lattice_size**2,
              "mean_Q_z": data.mean("q_z"), "mean_Q_plaquette": data.mean("q_plaq")}
    if (cpn_n is None) != (beta is None):
        raise ValueError("cpn_n and beta must be provided together")
    if cpn_n is not None:
        mean_extensive_energy = 2.0 * cpn_n * lattice_size**2 * action_density
        result["mean_extensive_energy"] = mean_extensive_energy
        result["mean_symanzik_action"] = beta * mean_extensive_energy
    return result


def evaluate_at_beta(data: CombinedNestedSampling, lattice_size: int,
                     source_beta: float, target_beta: float | None,
                     cpn_n: int | None
                     ) -> tuple[CombinedNestedSampling, dict[str, float]]:
    """Evaluate observables at the source beta or at one beta-reweighted target."""

    selected_beta = source_beta if target_beta is None else target_beta
    selected = data
    log_z_ratio = quadrature_ess = None
    if target_beta is not None:
        if cpn_n is None:
            raise ValueError("cpn_n is required for beta reweighting")
        selected, log_z_ratio, quadrature_ess = reweight_beta(
            data, source_beta, target_beta, cpn_n, lattice_size**2
        )

    values = quantities(
        selected,
        lattice_size,
        cpn_n=cpn_n,
        beta=selected_beta if cpn_n is not None else None,
    )
    # These describe coverage of the source prior, not a physical partition
    # function.  Keep log_Z temporarily as a compatibility alias.
    values = {
        "log_accumulated_prior_mass": data.log_z,
        "log_Z": data.log_z,
        "log_remaining_prior_mass": float(data.log_x[-1]),
        "remaining_prior_mass": float(np.exp(data.log_x[-1])),
        **values,
    }
    if log_z_ratio is not None:
        values["log_Z_ratio"] = log_z_ratio
        values["quadrature_effective_sample_size"] = quadrature_ess
    return selected, values


def plots(data: CombinedNestedSampling, streams: list[NestedSamplingStream], output: Path,
          values: dict[str, float], errors: dict[str, float]) -> None:
    x = -data.log_x
    fig, ax = plt.subplots(2, 1, figsize=(8, 8), constrained_layout=True)
    ax[0].plot(x, np.exp(data.log_weight_normalized)); ax[0].set_yscale("log")
    ax[0].set(xlabel=r"$-\log X$", ylabel="normalized weight")
    ax[1].plot(x, data.log_z_curve)
    ax[1].set(xlabel=r"$-\log X$", ylabel=r"$\log$ cumulative normalized weight")
    for a in ax: a.grid(alpha=.3)
    fig.savefig(output / "nested_sampling_weights_z.png", dpi=180); plt.close(fig)

    fig, ax = plt.subplots(2, 1, figsize=(8, 8), constrained_layout=True)
    for stream in streams:
        ax[0].plot(stream.observables["action_density"], lw=.7, alpha=.6,
                   label=Path(stream.name).name)
    ax[0].plot(np.linspace(0, max(map(lambda s: len(s.energy), streams)), len(data.energy)),
               data.observables["action_density"], color="black", label="combined")
    ax[0].set(xlabel="nested-sampling step", ylabel="action density")
    if len(streams) <= 25:
        ax[0].legend(fontsize=7, ncol=2)
    ax[1].hist([s.energy for s in streams], bins=50, density=True, alpha=.45)
    ax[1].set(xlabel="energy", ylabel="density")
    for a in ax: a.grid(alpha=.3)
    fig.savefig(output / "action_energy.png", dpi=180); plt.close(fig)

    fig, ax = plt.subplots(2, 1, figsize=(8, 8), constrained_layout=True)
    ax[0].plot(x, data.observables["g0"], lw=.6, label=r"$\tilde G(0)$")
    ax[0].plot(x, data.observables["gk"], lw=.6, label=r"$\tilde G(k)$")
    ax[0].set(xlabel=r"$-\log X$", ylabel="correlator"); ax[0].legend()
    ax[1].errorbar([0], [values["xi_L"]], yerr=[errors.get("xi_L", 0)], fmt="o", capsize=5)
    ax[1].set(xticks=[0], xticklabels=[r"$\xi_L$"], ylabel=r"$\xi_L$")
    for a in ax: a.grid(alpha=.3)
    fig.savefig(output / "correlation_length.png", dpi=180); plt.close(fig)

    fig, ax = plt.subplots(3, 1, figsize=(8, 10), constrained_layout=True)
    for a, key, label in zip(ax, ("q_u", "q_z", "q_plaq"), (r"$Q_U$", r"$Q_z$", r"$Q_{plaq}$")):
        a.plot(x, data.observables[key], ".", ms=2, alpha=.55)
        a.set(xlabel=r"$-\log X$", ylabel=label); a.grid(alpha=.3)
    fig.savefig(output / "topological_charge.png", dpi=180); plt.close(fig)


def main() -> None:
    args = arguments()
    if args.cpn_n is not None and args.cpn_n <= 0:
        raise ValueError("--cpn-n must be positive")
    if args.target_beta is not None:
        if args.cpn_n is None:
            raise ValueError("--cpn-n is required with --target-beta")
        if not np.isfinite(args.target_beta) or args.target_beta < 0.0:
            raise ValueError("--target-beta must be finite and non-negative")
    loaded = [load_run(p, args.action_prefactor, args.cooling_step) for p in discover_runs(args.run_roots)]
    streams, run_info = [x[0] for x in loaded], [x[1] for x in loaded]
    sizes = {tuple(x["size"]) for x in run_info}
    if len(sizes) != 1 or len(next(iter(sizes))) != 2 or len(set(next(iter(sizes)))) != 1:
        raise ValueError(f"runs must share one square lattice size; found {sizes}")
    length = next(iter(sizes))[0]
    source_betas = {x["beta"] for x in run_info}
    if len(source_betas) != 1 or not np.isfinite(next(iter(source_betas))):
        raise ValueError(f"runs must share one finite source beta; found {source_betas}")
    source_beta = next(iter(source_betas))
    thetas = {x["theta"] for x in run_info}
    if len(thetas) != 1 or not np.isfinite(next(iter(thetas))):
        raise ValueError(f"runs must share one finite fixed theta; found {thetas}")
    fixed_theta = next(iter(thetas))
    selected_beta = source_beta if args.target_beta is None else args.target_beta
    combined = combine_streams(streams)
    selected_combined, point_values = evaluate_at_beta(
        combined, length, source_beta, args.target_beta, args.cpn_n
    )

    def statistic(data: CombinedNestedSampling) -> dict[str, float]:
        return evaluate_at_beta(
            data, length, source_beta, args.target_beta, args.cpn_n
        )[1]

    if args.no_bootstrap:
        values, errors, samples = point_values, {}, {}
    else:
        values, errors, samples = bootstrap_nested_sampling(streams, statistic, args.bootstrap, args.seed)

    args.output.mkdir(parents=True, exist_ok=True)
    result = {"settings": {"action_prefactor": args.action_prefactor,
              "bootstrap_replicates": 0 if args.no_bootstrap else args.bootstrap,
              "seed": args.seed, "n_live_effective": combined.n_live_effective,
              "cpn_n": args.cpn_n, "source_beta": source_beta,
              "target_beta": selected_beta,
              "beta_reweighted": args.target_beta is not None,
              "fixed_theta": fixed_theta},
              "deprecated_estimate_aliases": {
                  "log_Z": "log_accumulated_prior_mass"
              },
              "runs": run_info, "estimates": values, "bootstrap_standard_errors": errors}
    (args.output / "results.json").write_text(json.dumps(result, indent=2, allow_nan=True) + "\n")
    with (args.output / "summary.txt").open("w", encoding="utf-8") as f:
        for key, value in values.items():
            f.write(f"{key}: {value:.12g}" + (f" +/- {errors[key]:.8g}" if key in errors else "") + "\n")
    if samples and args.save_bootstrap_samples:
        with (args.output / "bootstrap_samples.csv").open("w", newline="", encoding="utf-8") as f:
            keys = list(samples); writer = csv.writer(f); writer.writerow(["replicate", *keys])
            writer.writerows([i, *(samples[k][i] for k in keys)] for i in range(args.bootstrap))
    plots(selected_combined, streams, args.output, values, errors)
    print(f"Analyzed {len(streams)} runs ({len(combined.energy)} dead points).")
    if args.target_beta is not None:
        print(f"Reweighted beta {source_beta:g} -> {args.target_beta:g} (theta={fixed_theta:g} fixed).")
    print(f"Results written to {args.output.resolve()}")


if __name__ == "__main__":
    main()
