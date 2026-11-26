"""Write aggregate timing and prior diagnostics for the N=21 MCMC campaigns."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from statistics import median

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from utils.cpn_io import read_config
from utils.mcmc import OBSERVABLES, binning_analysis, load_ensemble


MODES = {
    "L72-b061": (72, 0.61, 10),
    "L72-b060": (72, 0.60, 1),
    "L150-timing": (150, 0.60, 1),
    "L150-prior": (150, 0.60, 1),
}


def save_rows(path, rows):
    with path.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=rows[0])
        writer.writeheader()
        writer.writerows(rows)


def autocorrelation(values, stride, lag_power=10):
    """Windowed tau_int in MC cycles and the ACF at specific MC-cycle lags."""
    values = np.asarray(values, dtype=float)
    centered = values - values.mean()
    variance = np.dot(centered, centered)
    lags = sorted({8} | {stride * 2**power for power in range(lag_power + 1)})
    estimates = dict.fromkeys(f"rho_lag_{lag}" for lag in lags)
    estimates.update(tau_int_cycles=None, effective_measurements=None, window_cycles=None)
    if variance == 0:
        return dict(status="constant", **estimates)

    length = len(values)
    maxlag = length // 10
    fft_size = 1 << (2 * length - 1).bit_length()
    transformed = np.fft.rfft(centered, n=fft_size)
    lag_indices = np.arange(1, maxlag + 1)
    covariance = np.fft.irfft(transformed * transformed.conj(), n=fft_size)[:maxlag + 1]
    rho = covariance / covariance[0] * length / (length - np.arange(maxlag + 1))
    estimates.update({f"rho_lag_{lag}": float(rho[lag // stride])
                      for lag in lags if lag % stride == 0 and lag // stride <= maxlag})
    tau = 0.5 + np.cumsum(rho[1:])
    windows = np.flatnonzero((tau > 0) & (lag_indices >= 10 * tau))
    if not len(windows):
        return dict(status="window_unresolved", **estimates)
    window = int(windows[0] + 1)
    value = float(tau[window - 1])
    estimates.update(tau_int_cycles=value * stride, effective_measurements=length / (2 * value),
                     window_cycles=window * stride)
    status = "window_found" if length >= 200 * value else "limited_history"
    return dict(status=status, **estimates)


def series(chain):
    return {"action_density": chain.action_density, "G0": chain.g0, "Gk": chain.gk,
            "Q_U": chain.q_u, "Q_U_squared": chain.q_u**2}


def run_checks(mode, job):
    lattice, beta, stride = MODES[mode]
    if not (job / "completed").is_file():
        raise ValueError(f"Missing simulation completion marker in {job}")
    rows, configs = [], []
    for index in range(4):
        run = job / f"run_{index}"
        config = read_config(run / "input.conf")
        actual = (tuple(map(int, config["size"])), float(config["beta"][0]),
                  int(config["meas_every"][0]), int(config["start"][0]))
        expected = ((lattice, lattice), beta, stride, 1)
        if actual != expected or not (run / "completed").is_file():
            raise ValueError(f"Expected a completed chain with the prescribed settings and a hot start: {run}")
        for key, value in {"theta": "0.0", "num_micro": "4", "num_norm": "1",
                           "num_cool_step": "50", "meas_cool_every": "5", "rng_start": "0",
                           "num_replica": "1"}.items():
            if config.get(key) != [value]:
                raise ValueError(f"Unexpected {key} in {run}")
        if "Theory: 2d CP^{N-1} model with N = 21" not in (run / "log.dat").read_text().splitlines():
            raise ValueError(f"Missing N=21 run banner in {run}")
        steps = int(config["num_MC_step"][0])
        timing = dict(line.split("=", 1) for line in (run / "timing.txt").read_text().splitlines())
        node, cpu = (run / "node.txt").read_text().splitlines()
        elapsed = float(timing["elapsed_seconds"])
        if not math.isfinite(elapsed) or elapsed <= 0 or steps < 1 or steps % stride:
            raise ValueError(f"Invalid timing or cycle count in {run}")
        rows.append(dict(chain=run.name, start="hot", seed=int(config["rng_seed"][0]),
                         lattice=lattice, beta=beta, node=node, cpu_model=cpu, cycles=steps,
                         measurement_stride=stride, elapsed_seconds=elapsed,
                         seconds_per_cycle=elapsed / steps,
                         user_seconds=float(timing["user_seconds"]),
                         system_seconds=float(timing["system_seconds"]),
                         max_rss_kib=int(timing["max_rss_kib"])))
        configs.append(config)
    if len({r["seed"] for r in rows}) != 4 or min(r["seed"] for r in rows) <= 0:
        raise ValueError("Expected four distinct positive seeds")
    if len({r["cycles"] for r in rows}) != 1:
        raise ValueError("Expected the same cycle count across chains")
    return rows, configs


def analyze_chains(mode, job, timing, output):
    target_reference = mode == "L72-b061"
    cuts = [0, 2000, 10000, 20000] if target_reference else [0, 20, 100, 500, 2000, 5000]
    long_prior = mode in ("L72-b060", "L150-prior") and timing[0]["cycles"] >= 200000
    if long_prior:
        cuts.extend((10000, 20000))
    lag_power = 14 if long_prior else 10
    chains = load_ensemble(job, cooling_step=25)
    if [chain.path.name for chain in chains] != [r["chain"] for r in timing]:
        raise ValueError("Chain directories do not match the four timed runs")
    for chain, row in zip(chains, timing):
        if not np.array_equal(chain.steps, np.arange(chain.meas_every, row["cycles"] + 1, chain.meas_every)):
            raise ValueError(f"Incomplete cycle history: {chain.path}")

    groups = {chain.path.name: [chain] for chain in chains}
    groups["pooled"] = chains
    blocking = []
    for cut in cuts:
        for name, group in groups.items():
            retained = [c.after_burn_in(cut) for c in group]
            for result in binning_analysis(retained):
                observables = [(key, val, se) for key, val, se in
                               zip(OBSERVABLES, result.estimate, result.standard_error)]
                epsilon, se_epsilon = result.estimate[0], result.standard_error[0]
                chi, se_chi = result.estimate[3], result.standard_error[3]
                volume = group[0].size[0] * group[0].size[1]
                observables.extend((("energy_per_NV", 2*epsilon, 2*se_epsilon),
                                    ("volume_times_chi", volume*chi, volume*se_chi)))
                for key, value, se in observables:
                    blocking.append(dict(group=name, burn_in_cycles=cut,
                                         block_cycles=result.block_size * group[0].meas_every,
                                         blocks=result.n_blocks, observable=key, estimate=value, se=se))
    save_rows(output / "binning.csv", blocking)
    acf_rows, sectors, windows = [], [], []
    for chain, run in zip(chains, timing):
        for cut in cuts[-2:]:
            kept = chain.after_burn_in(cut)
            charge = np.rint(kept.q_u)
            sectors.append(dict(chain=run["chain"], start=run["start"], burn_in_cycles=cut,
                                measurements=len(charge), unique_sectors=len(np.unique(charge)),
                                transitions=int(np.count_nonzero(np.diff(charge))),
                                min_sector=int(charge.min()), max_sector=int(charge.max())))
            for key, values in series(kept).items():
                acf_rows.append(dict(chain=run["chain"], start=run["start"], burn_in_cycles=cut,
                                     observable=key,
                                     **autocorrelation(values, chain.meas_every, lag_power)))
        if not target_reference:
            # The NS initializer saves its first configuration after cycle 21.
            samples = 50
            window_specs = [("initial_20_8", 21, 8), ("late_20_8", cuts[-1] + 1, 8)]
            if long_prior:
                for spacing in (512, 1024, 2048):
                    last_start = len(chain.steps) - (samples - 1) * spacing
                    starts = range(cuts[-1] + 1, last_start + 1, samples * spacing)
                    window_specs.extend((f"late_s{spacing}_{index}", start, spacing)
                                        for index, start in enumerate(starts, 1))
            observables = series(chain)
            for label, start, spacing in window_specs:
                steps = start + spacing * np.arange(samples)
                for key, values in observables.items():
                    picked = values[steps - 1]
                    windows.append(dict(chain=run["chain"], start=run["start"], window=label,
                                        first_cycle=int(steps[0]), last_cycle=int(steps[-1]),
                                        observable=key, mean=float(picked.mean()), sd=float(picked.std(ddof=1))))
    save_rows(output / "autocorrelation.csv", acf_rows)
    save_rows(output / "charge_sectors.csv", sectors)
    if windows:
        save_rows(output / "live_spacing_windows.csv", windows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=MODES)
    parser.add_argument("job", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        timing, configs = run_checks(args.mode, args.job.resolve())
        args.output.mkdir()
        save_rows(args.output / "timing.csv", timing)
        rates = [row["seconds_per_cycle"] for row in timing]
        summary = dict(mode=args.mode, source_job=str(args.job.resolve()), cooling_step=25,
                       median_seconds_per_cycle=median(rates), range_seconds_per_cycle=[min(rates), max(rates)],
                       runs=configs, timing_metric="Process wall time divided by MC cycles")
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        if args.mode != "L150-timing":
            analyze_chains(args.mode, args.job, timing, args.output)
        (args.output / "completed").touch()
        print(f"Median {summary['median_seconds_per_cycle']:.6f} wall s/MC cycle; outputs: {args.output}")
    except (OSError, ValueError, KeyError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
