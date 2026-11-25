#!/usr/bin/env python3
"""Analyze source-prior hot/cold pilots or a separate high-proposal NS ensemble."""

from __future__ import annotations

import argparse
from functools import partial
from pathlib import Path
import sys
from types import SimpleNamespace

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.check_ensemble_robustness import save_rows, statistic, unpack, write_comparison
from N4_volume_benchmark.compare_action_bins import mcmc_block_totals
from N4_volume_benchmark.scan_depth import common_prefix, load_ns_ensemble, scan
from N4_volume_benchmark.scan_stream_count import old_new_differences, result_rows, write_json
from utils.cpn_io import discover_runs, read_config
from utils.mcmc import OBSERVABLES as MC_OBSERVABLES, binning_analysis, load_ensemble
from utils.nest_sampl import bootstrap_nested_sampling


def verify_mcmc_logs(chains, lattice, beta):
    for chain in chains:
        config = read_config(chain.path / "input.conf")
        log = chain.path / config.get("log_file", ["log.dat"])[0]
        if ((chain.size, chain.beta, chain.theta, chain.cooling_step) != ((lattice, lattice), beta, 0., 50)
                or "Theory: 2d CP^{N-1} model with N = 4" not in log.read_text().splitlines()):
            raise ValueError(f"Unexpected MCMC settings or N=4 log: {chain.path}")


def autocorrelation(values):
    """FFT ACF and a self-consistent window; tau_int = 1/2 + sum rho.

    Window W >= 10*tau_int corresponds to W >= 5*(1+2*sum rho).
    Reliability is a heuristic, not a stationarity or thermalization test.
    """
    values = np.asarray(values, dtype=float)
    if len(values) < 32 or not np.isfinite(values).all():
        raise ValueError("Need at least 32 finite measurements for the ACF")
    centered = values - values.mean()
    variance = np.dot(centered, centered) / len(values)
    if variance == 0:
        return dict(tau_int=None, window=None, rho8=None, reliable=False, status="constant_series"), None
    size = 1 << (2 * len(values) - 1).bit_length()
    transformed = np.fft.rfft(centered, n=size)
    maxlag = min(len(values) // 10, 2000)
    covariance = np.fft.irfft(transformed * transformed.conj(), n=size)[:maxlag + 1]
    covariance /= len(values) - np.arange(maxlag + 1)
    rho = covariance / covariance[0]
    tau = .5 + np.cumsum(rho[1:])
    candidates = np.flatnonzero((tau > 0) & (np.arange(1, maxlag + 1) >= 10 * tau))
    window = int(candidates[0] + 1) if len(candidates) else maxlag
    value = float(tau[window - 1])
    reliable = bool(len(candidates) and value > 0 and len(values) >= 200 * value)
    return dict(tau_int=value, window=window, rho8=float(rho[8]) if maxlag >= 8 else None,
                reliable=reliable, status="window_found" if len(candidates) else "window_unresolved"), rho


def analyze_source(args):
    chains = load_ensemble(args.mcmc)
    verify_mcmc_logs(chains, args.lattice, .7)
    starts = [int(read_config(c.path / "input.conf")["start"][0]) for c in chains]
    if len(chains) != 4 or starts.count(0) != 2 or starts.count(1) != 2:
        raise ValueError("Need two cold(start=0) and two hot(start=1) chains")
    if any(c.meas_every != 1 for c in chains):
        raise ValueError("Source pilot must measure every MC cycle")
    if max(args.cuts) >= min(c.steps[-1] for c in chains) or args.acf_burn not in args.cuts:
        raise ValueError("Burn-in cuts must leave data; ACF cut must be included in cut scan")
    args.output.mkdir(parents=True, exist_ok=False)
    write_json(args.output / "inputs.json", dict(mcmc=str(args.mcmc.resolve()), lattice=args.lattice,
               beta=.7, cuts=args.cuts, acf_burn=args.acf_burn, starts=starts,
               runs=[str(c.path) for c in chains], seeds=[c.seed for c in chains]))
    cut_rows, block_rows = [], []
    groups = [(c.path.name, [c]) for c in chains] + [
        ("cold2", [c for c, start in zip(chains, starts) if start == 0]),
        ("hot2", [c for c, start in zip(chains, starts) if start == 1])]
    for burn in args.cuts:
        for name, group in groups:
            retained = [c.after_burn_in(burn) for c in group]
            results = binning_analysis(retained)
            chosen = max((r for r in results if r.block_size <= 128), key=lambda r:r.block_size)
            for row in results:
                for key, mean, se in zip(MC_OBSERVABLES, row.estimate, row.standard_error):
                    block_rows.append(dict(group=name, burn_in=burn, block_measurements=row.block_size,
                                           blocks=row.n_blocks, observable=key, estimate=mean, se=se))
            for key, mean, se in zip(MC_OBSERVABLES, chosen.estimate, chosen.standard_error):
                cut_rows.append(dict(group=name, burn_in=burn, block_measurements=chosen.block_size,
                                     observable=key, estimate=mean, se=se))
    save_rows(args.output / "cut_scan.csv", cut_rows)
    save_rows(args.output / "binning.csv", block_rows)
    acf_rows, curve_rows, live_rows = [], [], []
    fig, axes = plt.subplots(2, 3, figsize=(12, 7), constrained_layout=True)
    keys = ("action_density", "G0", "Gk", "Q", "Q_squared")
    for chain, start in zip(chains, starts):
        retained = chain.after_burn_in(args.acf_burn)
        for axis, key, values in zip(axes.flat, keys, (retained.action_density, retained.g0, retained.gk, retained.q_u, retained.q_u**2)):
            result, rho = autocorrelation(values)
            acf_rows.append(dict(chain=chain.path.name, start=start, observable=key,
                                 burn_in=args.acf_burn, measurements=len(values), **result))
            if rho is not None:
                take = min(len(rho), max(51, 3 * result["window"] + 1))
                axis.plot(np.arange(take), rho[:take], label=chain.path.name + (" cold" if start == 0 else " hot"))
                curve_rows.extend(dict(chain=chain.path.name, observable=key, lag=i, rho=float(value)) for i, value in enumerate(rho))
            axis.set(title=key, xlabel="Lag (MC cycles)", ylabel="Autocorrelation")
        for label, first in (("initial_20_8", 21), ("late_20_8", args.acf_burn + 1)):
            steps = first + 8 * np.arange(50)
            indices = np.searchsorted(chain.steps, steps)
            if np.any(indices >= len(chain.steps)) or not np.array_equal(chain.steps[indices], steps):
                raise ValueError("Source pilot is too short for the 50-point spacing comparison")
            for key, values in zip(keys, (chain.action_density, chain.g0, chain.gk, chain.q_u, chain.q_u**2)):
                live_rows.append(dict(chain=chain.path.name, start=start, window=label, first_step=int(steps[0]),
                                      last_step=int(steps[-1]), points=50, spacing=8, observable=key,
                                      mean=float(values[indices].mean()), sd=float(values[indices].std(ddof=1))))
    axes.flat[-1].axis("off")
    handles, labels = axes.flat[0].get_legend_handles_labels()
    axes.flat[-1].legend(handles, labels, loc="center")
    fig.savefig(args.output / "autocorrelation.png", dpi=150); plt.close(fig)
    save_rows(args.output / "autocorrelation.csv", acf_rows)
    if curve_rows:
        save_rows(args.output / "autocorrelation_curves.csv", curve_rows)
    save_rows(args.output / "live_spacing_windows.csv", live_rows)
    for limit, name in ((1000, "histories_early.png"), (None, "histories_full.png")):
        fig, axes = plt.subplots(2, 2, figsize=(12, 6), constrained_layout=True)
        for axis, key, attribute in zip(axes.flat, keys, ("action_density", "g0", "gk", "q_u")):
            for chain, start in zip(chains, starts):
                selected = np.arange(len(chain.steps)) if limit is None else np.flatnonzero(chain.steps <= limit)
                axis.plot(chain.steps[selected], getattr(chain, attribute)[selected], alpha=.65,
                          linewidth=.6, label=chain.path.name + (" cold" if start == 0 else " hot"))
            axis.axvline(20, color="0.3", linestyle="--", label="20-cycle warmup")
            axis.axvline(413, color="0.6", linestyle=":", label="Last initial live point")
            axis.set(title=key, xlabel="MC cycles", ylabel=key)
            if attribute in ("g0", "gk") and all(np.min(getattr(c, attribute)) > 0 for c in chains):
                axis.set_yscale("log")
        axes.flat[0].legend(fontsize=7)
        fig.savefig(args.output / name, dpi=150); plt.close(fig)
    (args.output / "completed").touch()
    print(f"Source-prior diagnostics saved: {args.output}. Assess thermalization and spacing separately.")


def analyze_proposals(args):
    base_cfg, base_data = load_ns_ensemble(args.baseline)
    test_cfg, test_data = load_ns_ensemble(args.control)
    if (len(base_data), len(test_data)) != (24, 8):
        raise ValueError("Expected baseline24 and separate control8")
    for cfg, data, expected in ((base_cfg, base_data, 86400), (test_cfg, test_data, 172800)):
        if (tuple(map(int, cfg["size"])), int(cfg["num_single_site_stoc_upd"][0]),
            int(cfg["num_live_pts"][0]), int(cfg["num_MC_step"][0]), int(cfg["meas_every"][0])) != ((args.lattice, args.lattice), expected, 50, 20, 8):
            raise ValueError("Unexpected proposal comparison settings")
        if any(len(c) - 1 != args.updates for c in data):
            raise ValueError("Expected exactly the requested cumulative NS depth")
    if {k:v for k,v in base_cfg.items() if k not in {"rng_seed", "num_single_site_stoc_upd"}} != {
            k:v for k,v in test_cfg.items() if k not in {"rng_seed", "num_single_site_stoc_upd"}}:
        raise ValueError("Proposal count must be the only configuration difference")
    paths = discover_runs(args.baseline + args.control)
    seeds = [int(read_config(p / "input.conf")["rng_seed"][0]) for p in paths]
    if len(paths) != 32 or len(set(seeds)) != 32:
        raise ValueError("Use 32 distinct baseline/control NS seeds")
    chains = [c.after_burn_in(20000) for c in load_ensemble(args.mcmc)]
    verify_mcmc_logs(chains, args.lattice, 1.)
    if len(chains) != 3 or set(seeds) & {c.seed for c in chains} or any(len(c.steps) < 8192 for c in chains):
        raise ValueError("Need three independent reference chains with >=16 blocks of 512")
    actions = np.concatenate([c.action_density[:len(c.steps)//512*512] for c in chains])
    edges = np.quantile(actions, np.linspace(.005, .995, 33))
    cutoff = max(c[args.updates, 0] for c in (*base_data, *test_data))
    if np.any(np.diff(edges) <= 0) or cutoff >= edges[0]:
        raise ValueError("Invalid bin edges or inadequate common NS depth")
    streams = common_prefix([*base_data, *test_data], args.updates, 50)
    blocks = mcmc_block_totals(chains, 512, edges)
    mc = next(r for r in binning_analysis(chains) if r.block_size == 512)
    reference = {key:dict(estimate=float(value), se=float(se)) for key,value,se in zip(MC_OBSERVABLES, mc.estimate, mc.standard_error)}
    settings = dict(bins=32, mcmc_reference=reference)
    args.output.mkdir(parents=True, exist_ok=False)
    write_json(args.output / "inputs.json", dict(baseline=[str(p) for p in args.baseline], control=[str(p) for p in args.control],
               mcmc=str(args.mcmc), updates=args.updates, seed=args.seed, bootstrap=args.bootstrap,
               joint_draws=args.joint_draws, common_epsilon_cutoff=float(cutoff), edges=edges.tolist()))
    results = {}
    stat = partial(statistic, edges={32:edges}, lattice=args.lattice, beta=1.)
    for i, (name, ids) in enumerate((("baseline24", list(range(24))), ("control8", list(range(24,32))))):
        print(f"Bootstrapping {name}", flush=True)
        values, errors, draws = bootstrap_nested_sampling([streams[j] for j in ids], stat, args.bootstrap, args.seed+i)
        rows, bins = result_rows(name, ids, values, errors, draws, edges, blocks, settings)
        write_comparison(args.output / name, edges, unpack(values,32), unpack(draws,32), blocks,
                         args.joint_draws, args.seed+100+i, f"L={args.lattice}, β=1, {name}")
        results[name] = dict(observables=rows, bins=bins)
    save_rows(args.output / "observables.csv", [r for result in results.values() for r in result["observables"]])
    save_rows(args.output / "proposal_differences.csv", old_new_differences(results["baseline24"], results["control8"]))
    # The new proposal count is a separate ensemble, never merged with baseline24.
    print("Scanning control8 depth", flush=True)
    depth_args = SimpleNamespace(updates=getattr(args, "depths", [240000,270000,300000]),
                                 targets=[1.], bootstrap=args.bootstrap, seed=args.seed)
    save_rows(args.output / "control_depth.csv", scan(test_data, args.lattice, 50, depth_args))
    (args.output / "completed").touch()
    print(f"Proposal sensitivity results saved: {args.output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    p = modes.add_parser("source")
    p.add_argument("--mcmc", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--lattice", type=int, default=120)
    p.add_argument("--cuts", type=int, nargs="+", default=[0,20,100,500,1000,2000])
    p.add_argument("--acf-burn", type=int, default=2000)
    p = modes.add_parser("proposals")
    p.add_argument("--baseline", type=Path, nargs=6, required=True)
    p.add_argument("--control", type=Path, nargs=2, required=True)
    p.add_argument("--mcmc", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--lattice", type=int, default=120)
    p.add_argument("--updates", type=int, default=300000)
    p.add_argument("--bootstrap", type=int, default=200)
    p.add_argument("--joint-draws", type=int, default=1000)
    p.add_argument("--seed", type=int, default=20261125)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; use a new analysis job directory")
    if args.mode == "source" and (min(args.cuts) < 0 or len(set(args.cuts)) != len(args.cuts)):
        parser.error("Use distinct nonnegative burn-in cuts")
    if args.mode == "proposals" and (args.bootstrap < 2 or args.joint_draws < 2 or args.seed < 0 or args.updates != 300000):
        parser.error("Use >=2 draws, nonnegative seed and exactly 300000 updates")
    try:
        (analyze_source if args.mode == "source" else analyze_proposals)(args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
