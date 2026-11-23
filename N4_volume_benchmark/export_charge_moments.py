#!/usr/bin/env python3
"""Export all three topological-charge means and second moments from raw runs."""

import argparse
import csv
import hashlib
from itertools import islice
import json
from pathlib import Path
import sys

import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.scan_depth import common_prefix, load_ns_ensemble
from utils.cpn_io import discover_runs, read_config
from utils.mcmc import block_means
from utils.nest_sampl import bootstrap_nested_sampling, reweight_beta


REPO = Path(__file__).resolve().parents[1]
CHARGES = (("Q_U", "q_u"), ("Q_z", "q_z"), ("Q_plaquette", "q_plaq"))
QUANTITIES = tuple(key for name, _ in CHARGES for key in (f"mean_{name}", f"mean_{name}_squared"))
PLANS = {
    22: (100, 50000, 1500, .7, "mcmc_22_N4_beta0p7_3x1M/job_21347214"),
    38: (24, 35000, 8664, 1., "mcmc_38_N4_beta1p0_3x100k/job_22121710"),
    66: (12, 110000, 26136, .9, "mcmc_66_N4_beta0p9_3x100k/job_22587511"),
    90: (12, 210000, 48600, .95, "mcmc_90_N4_beta0p95_3x100k/job_22635137"),
    120: (12, 300000, 86400, 1., "mcmc_120_N4_beta1p0_3x100k/job_22780263"),
}
LARGE_MANIFESTS = {
    90: "N4_L90_res/combined210_ns22810844_analysis_22810847/inputs.tsv",
    120: "N4_L120_res/combined300_ns22885157_analysis_22904265/inputs.tsv",
}


def scratch_path(saved, scratch):
    """Remap historical /rs_scratch paths to the selected out_data root."""
    suffix = str(saved).split("/out_data/", 1)
    if len(suffix) != 2 or ".." in Path(suffix[1]).parts:
        raise ValueError(f"Expected an absolute saved out_data path: {saved}")
    remapped = scratch / suffix[1]
    if remapped.exists():
        return remapped
    original = Path(saved)
    if original.is_absolute() and original.exists():
        return original
    raise FileNotFoundError(f"Missing scratch input: {remapped} (saved path: {saved})")


def campaign_inputs(lattice, scratch):
    expected, updates, proposals, mc_beta, mc_relative = PLANS[lattice]
    if lattice in (22, 38, 66):
        manifest = REPO / f"N4_L66_res/volume_scan.T1n611/L{lattice}/inputs.json"
        saved = json.loads(manifest.read_text(encoding="utf-8"))
        roots = [scratch_path(path, scratch) for path in saved["runs"]]
        targets = tuple(saved["betas"])
        if int(saved["depth"]) != updates:
            raise ValueError(f"Unexpected saved depth in {manifest}")
    else:
        manifest = REPO / LARGE_MANIFESTS[lattice]
        with manifest.open(newline="", encoding="utf-8") as handle:
            records = list(csv.DictReader(handle, delimiter="\t"))
        roots = [scratch_path(row["directory"], scratch) for row in records if row["kind"] == "ns"]
        targets = (.9, .95, 1.)
    paths = discover_runs(roots)
    if len(paths) != expected:
        raise ValueError(f"Expected {expected} NS streams for L{lattice}, found {len(paths)}")
    mc_root = scratch / mc_relative
    if not mc_root.is_dir():
        raise FileNotFoundError(f"Missing MCMC reference: {mc_root}")
    return paths, mc_root, targets, updates, proposals, mc_beta, manifest


def charge_statistic(data, lattice, targets):
    result = {}
    for beta in targets:
        weighted, _, _ = reweight_beta(data, .7, beta, 4, lattice ** 2)
        for name, observable in CHARGES:
            result[f"{beta}/mean_{name}"] = weighted.mean(observable)
            result[f"{beta}/mean_{name}_squared"] = weighted.weighted_sum(weighted.observables[observable] ** 2)
    return result


def load_mc_charges(root, lattice, beta, burn_in, expected_chains=3):
    """Stream only final-cooling rows; retain aligned Q_U, Q_z and Q_plaq."""
    chains, provenance, settings, seeds = [], [], None, set()
    paths = discover_runs([root])
    if len(paths) != expected_chains:
        raise ValueError(f"Expected {expected_chains} MCMC chains in {root}")
    for path in paths:
        config = read_config(path / "input.conf")
        if "num_ns_meas" in config:
            raise ValueError(f"Expected MCMC input: {path}")
        seed = int(config["rng_seed"][0])
        if seed <= 0 or seed in seeds:
            raise ValueError("MCMC seeds must be distinct and positive")
        seeds.add(seed)
        cooling = int(config["num_cool_step"][0])
        spacing = int(config["meas_cool_every"][0])
        cadence = int(config["meas_every"][0])
        if min(spacing, cadence) < 1 or cooling < 0:
            raise ValueError(f"Invalid measurement cadence in {path}")
        final_cooling = cooling // spacing * spacing
        current = (tuple(map(int, config["size"])), float(config["beta"][0]),
                   float(config["theta"][0]), final_cooling, cadence)
        if current[:3] != ((lattice, lattice), beta, 0.) or (settings is not None and current != settings):
            raise ValueError(f"Incompatible MCMC settings: {path}")
        settings = current
        log = (path / "log.dat").read_text()
        if "Theory: 2d CP^{N-1} model with N = 4\n" not in log or "Simulation end:" not in log:
            raise ValueError(f"Expected a completed N=4 MCMC run: {path}")
        raw_steps = np.loadtxt(path / config["data_file"][0], usecols=0, ndmin=1)
        steps = raw_steps.astype(np.int64)
        expected_last = int(config["num_MC_step"][0]) // cadence * cadence
        if (not np.array_equal(raw_steps, steps) or not len(steps) or steps[0] < 0
                or np.any(steps % cadence) or np.any(np.diff(steps) != cadence) or steps[-1] != expected_last):
            raise ValueError(f"Incomplete or irregular MCMC measurements: {path}")
        with (path / config["topo_file"][0]).open() as handle:
            rows = (line for line in handle if line.strip() and not line.lstrip().startswith("#"))
            topo = np.loadtxt(islice(rows, cooling // spacing, None, cooling // spacing + 1),
                              usecols=(0, 1, 2, 3, 4), ndmin=2)
        if (len(topo) != len(steps) or not np.array_equal(topo[:, 0], steps)
                or not np.all(topo[:, 1] == final_cooling) or not np.isfinite(topo).all()):
            raise ValueError(f"Misaligned final-cooling topology: {path}")
        retained = topo[steps > burn_in, 2:5]
        if not len(retained):
            raise ValueError(f"No measurements after burn-in in {path}")
        chains.append(retained)
        provenance.append({"path": str(path), "seed": seed, "retained_measurements": len(retained),
                           "cooling_step": final_cooling, "meas_every": cadence})
    return chains, provenance


def blocked_charge_moments(chains, block_size):
    """Pool complete blocks without crossing chains; delete-one-block jackknife."""
    blocks = []
    dropped = []
    for charges in chains:
        values = np.column_stack([value for index in range(3)
                                  for value in (charges[:, index], charges[:, index] ** 2)])
        if len(values) // block_size < 16:
            raise ValueError("Each MCMC chain needs at least sixteen complete blocks")
        blocks.append(block_means(values, block_size))
        dropped.append(len(values) % block_size)
    blocks = np.concatenate(blocks)
    count = len(blocks)
    totals = blocks.sum(axis=0)
    estimate = totals / count
    replicates = (totals - blocks) / (count - 1)
    error = np.sqrt(count - 1) * np.std(replicates, axis=0)
    return estimate, error, count, dropped


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def analyze(ns_paths, mc_root, output, lattice, targets, updates, proposals, mc_beta,
            bootstrap=200, seed=20261123, burn_in=20000, block_size=128, manifest=None):
    if bootstrap < 2 or burn_in < 0 or block_size < 1 or updates < 1:
        raise ValueError("Require bootstrap >= 2, burn-in >= 0, positive block size and depth")
    # Validate the MC input before starting the more expensive NS bootstrap.
    mc_chains, mc_info = load_mc_charges(mc_root, lattice, mc_beta, burn_in)
    config, chains = load_ns_ensemble(ns_paths)
    if (tuple(map(int, config["size"])) != (lattice, lattice)
            or int(config["num_single_site_stoc_upd"][0]) != proposals):
        raise ValueError("NS lattice or proposal count differs from the saved campaign")
    if min(len(chain) - 1 for chain in chains) < updates:
        raise ValueError(f"NS streams do not reach {updates} updates")
    streams = common_prefix(chains, updates, int(config["num_live_pts"][0]))
    del chains
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"L": lattice, "cpn_n": 4, "source_beta": .7, "theta": 0.,
                "targets": list(targets), "updates": updates, "NS_streams": len(streams),
                "proposals": proposals, "NS_paths": [str(path) for path in ns_paths],
                "bootstrap": bootstrap, "seed": seed, "burn_in_MC_steps": burn_in,
                "block_size_measurements": block_size, "MCMC_beta": mc_beta, "MCMC_chains": mc_info,
                "quantities": list(QUANTITIES),
                "NS_error": "whole-stream bootstrap; merge and reweight each replicate",
                "MCMC_error": "delete-one-complete-block jackknife; incomplete tails discarded per chain",
                "second_moment": "Weighted mean of each measured Q squared; not mean(Q) squared",
                "support": "Same common-energy-support prefix convention as saved volume/depth scans"}
    if manifest is not None:
        metadata["selection_manifest"] = str(manifest)
        metadata["selection_manifest_sha256"] = hashlib.sha256(manifest.read_bytes()).hexdigest()
    (output / "inputs.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"L{lattice}: bootstrapping {len(streams)} NS streams at {updates} updates, targets {targets}", flush=True)
    estimates, errors, _ = bootstrap_nested_sampling(
        streams, lambda data: charge_statistic(data, lattice, targets), bootstrap, seed)
    rows = [{"method": "NS", "L": lattice, "beta": beta, "observable": key,
             "estimate": estimates[f"{beta}/{key}"], "standard_error": errors[f"{beta}/{key}"],
             "input_file": str(output / "inputs.json")} for beta in targets for key in QUANTITIES]
    write_csv(output / "ns_charge_moments.csv", rows)
    estimate, error, n_blocks, dropped = blocked_charge_moments(mc_chains, block_size)
    mc_rows = [{"method": "MCMC", "L": lattice, "beta": mc_beta, "observable": key,
                "estimate": float(value), "standard_error": float(se),
                "input_file": str(output / "inputs.json")} for key, value, se in zip(QUANTITIES, estimate, error)]
    write_csv(output / "mcmc_charge_moments.csv", mc_rows)
    write_csv(output / "charge_moments.csv", rows + mc_rows)
    metadata.update(MCMC_complete_blocks=n_blocks, MCMC_dropped_tail_measurements=dropped)
    (output / "inputs.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (output / "completed").write_text("All six NS and MCMC charge moments exported.\n", encoding="utf-8")
    print(f"L{lattice}: wrote {len(rows)} NS and {len(mc_rows)} MCMC estimates to {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lattice", type=int, choices=PLANS, required=True)
    parser.add_argument("--scratch-root", type=Path, default=Path("/scratch/network/users/lb25v444/out_data"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap", type=int, default=200)
    parser.add_argument("--seed", type=int, default=20261123)
    parser.add_argument("--burn-in", type=int, default=20000)
    parser.add_argument("--block-size", type=int, default=128)
    args = parser.parse_args()
    if not args.scratch_root.is_absolute():
        parser.error("--scratch-root must be absolute")
    ns, mc, targets, updates, proposals, mc_beta, manifest = campaign_inputs(args.lattice, args.scratch_root)
    analyze(ns, mc, args.output, args.lattice, targets, updates, proposals, mc_beta,
            args.bootstrap, args.seed, args.burn_in, args.block_size, manifest)


if __name__ == "__main__":
    main()
