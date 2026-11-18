#!/usr/bin/env python3
"""Compare N=4 L22/L38 beta scans and optional direct MCMC ensembles."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.scan_volume_betas import BETAS, QUANTITIES
from utils.cpn_io import discover_runs, read_config
from utils.mcmc import OBSERVABLES, binning_analysis, load_ensemble


def read_scan(path, lattice):
    with path.open(newline="", encoding="utf-8") as file:
        rows = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(file)]
    if (len(rows) != len(BETAS) or any(row["L"] != lattice for row in rows)
            or not np.allclose(sorted(row["target_beta"] for row in rows), BETAS, rtol=0, atol=1e-12)):
        raise ValueError(f"Expected the seven requested betas for L={lattice} in {path}")
    expected_stoc = 1500 if lattice == 22 else 8664
    if any(row["stochastic_proposals"] != expected_stoc for row in rows):
        raise ValueError(f"Expected {expected_stoc} stochastic proposals in {path}")
    return [{"method": "NS", **row} for row in sorted(rows, key=lambda row: row["target_beta"])]


def complete_mcmc_root(root):
    """Recognize a complete three-chain fresh MCMC job without loading topology."""
    try:
        paths = discover_runs([root])
        if len(paths) != 3:
            return False
        for path in paths:
            config = read_config(path / "input.conf")
            if int(config["start"][0]) != 1:
                return False
            log = (path / "log.dat").read_text()
            if "Theory: 2d CP^{N-1} model with N = 4\n" not in log or "Simulation end:" not in log:
                return False
            # Completed fresh chains end at the last scheduled measurement.
            with (path / config["data_file"][0]).open("rb") as file:
                file.seek(0, 2)
                file.seek(max(0, file.tell() - 4096))
                last = file.read().decode("ascii").splitlines()[-1].split()
            expected = int(config["num_MC_step"][0]) // int(config["meas_every"][0]) * int(config["meas_every"][0])
            if int(last[0]) != expected or not (path / config["topo_file"][0]).is_file():
                return False
        return True
    except (OSError, ValueError, KeyError, IndexError):
        return False


def mcmc_point(root, lattice, burn_in, block_size, output):
    if not complete_mcmc_root(root):
        raise ValueError(f"Expected a completed three-chain fresh N=4 MCMC job: {root}")
    chains = [chain.after_burn_in(burn_in) for chain in load_ensemble(root)]
    if chains[0].size != (lattice, lattice) or chains[0].theta != 0 or chains[0].cooling_step != 50:
        raise ValueError(f"Expected L={lattice}, theta=0 and cooling step 50 in {root}")
    results = binning_analysis(chains)
    selected = next((result for result in results if result.block_size == block_size), None)
    if selected is None:
        raise ValueError(f"Block size {block_size} unavailable in {root}; available: {[r.block_size for r in results]}")
    fields = ["block_size", "n_blocks", *OBSERVABLES, *(f"{key}_se" for key in OBSERVABLES)]
    with (output / f"mcmc_L{lattice}_binning.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        for result in results:
            writer.writerow({"block_size": result.block_size, "n_blocks": result.n_blocks,
                             **dict(zip(OBSERVABLES, result.estimate)),
                             **dict(zip((f"{key}_se" for key in OBSERVABLES), result.standard_error))})
    row = {"method": "MCMC", "L": lattice, "target_beta": chains[0].beta, "chains": len(chains),
           "burn_in_MC_steps": burn_in, "block_size_measurements": block_size,
           "measurements_per_block_MC_steps": block_size * chains[0].meas_every,
           "n_blocks": selected.n_blocks, "input_root": str(root),
           **dict(zip(OBSERVABLES, selected.estimate)),
           **dict(zip((f"{key}_bootstrap_se" for key in OBSERVABLES), selected.standard_error))}
    # This column is called *_se in the final comparison; the MCMC errors are
    # blocked jackknife errors. Only the derived sqrt uses the delta method.
    xi_sq = row["xi_L_squared"]
    row["xi_L"] = np.sqrt(xi_sq) if xi_sq > 0 else np.nan
    row["xi_L_bootstrap_se"] = row["xi_L_squared_bootstrap_se"] / (2 * row["xi_L"])
    row["xi_L_over_L"] = row["xi_L"] / lattice
    row["xi_L_over_L_bootstrap_se"] = row["xi_L_bootstrap_se"] / lattice
    return row


def compare(l22, l38, output, mcmc_l22=None, mcmc_l38=None,
            mcmc_l22_search=None, burn_in=20000, block_size=128):
    output.mkdir(parents=True, exist_ok=True)
    rows = read_scan(l22, 22) + read_scan(l38, 38)
    status = []
    if mcmc_l22 is None and mcmc_l22_search is not None:
        candidates = sorted(path for path in mcmc_l22_search.glob("job_*") if complete_mcmc_root(path))
        if len(candidates) == 1:
            mcmc_l22 = candidates[0]
        else:
            status.append(f"L22 MCMC: found {len(candidates)} completed candidates under {mcmc_l22_search}; "
                          "set MCMC_L22_DIR explicitly to include a reference.")
    for lattice, root in ((22, mcmc_l22), (38, mcmc_l38)):
        if root is not None:
            rows.append(mcmc_point(root, lattice, burn_in, block_size, output))
            status.append(f"L{lattice} MCMC: {root} (direct beta {rows[-1]['target_beta']})")
        elif lattice == 38 or mcmc_l22_search is None:
            status.append(f"L{lattice} MCMC: no directory supplied.")

    comparison = []
    for row in rows:
        clean = {key: value for key, value in row.items() if not key.endswith("_bootstrap_se")}
        for key in QUANTITIES:
            if f"{key}_bootstrap_se" in row:
                clean[f"{key}_se"] = row[f"{key}_bootstrap_se"]
        comparison.append(clean)
    fields = list(dict.fromkeys(key for row in comparison for key in row))
    with (output / "volume_comparison.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        writer.writerows(comparison)
    # Independent volumes/algorithms: variances add for these differences.
    # Errors do not include finite-depth or constrained-chain mixing bias.
    common = ("mean_action_density", "mean_G0", "mean_Gk", "mean_Q_U",
              "mean_Q_U_squared", "chi_topological", "xi_L_squared", "xi_L_over_L")
    shifts, checks = [], []
    for beta in BETAS:
        small = next(row for row in comparison if row["method"] == "NS" and row["L"] == 22 and row["target_beta"] == beta)
        large = next(row for row in comparison if row["method"] == "NS" and row["L"] == 38 and row["target_beta"] == beta)
        for key in common:
            shifts.append({"target_beta": beta, "observable": key,
                           "L22": small[key], "L22_se": small[f"{key}_se"],
                           "L38": large[key], "L38_se": large[f"{key}_se"],
                           "L38_minus_L22": large[key] - small[key],
                           "difference_se": np.hypot(small[f"{key}_se"], large[f"{key}_se"])})
    for mc in (row for row in comparison if row["method"] == "MCMC"):
        ns = next((row for row in comparison if row["method"] == "NS" and row["L"] == mc["L"]
                   and np.isclose(row["target_beta"], mc["target_beta"], rtol=0, atol=1e-12)), None)
        if ns is not None:
            for key in common:
                error = np.hypot(ns[f"{key}_se"], mc[f"{key}_se"])
                difference = ns[key] - mc[key]
                checks.append({"L": mc["L"], "target_beta": mc["target_beta"], "observable": key,
                               "NS": ns[key], "NS_se": ns[f"{key}_se"], "MCMC": mc[key],
                               "MCMC_se": mc[f"{key}_se"], "NS_minus_MCMC": difference,
                               "difference_se": error,
                               "difference_in_standard_errors": difference / error if error > 0 else np.nan})
    for name, table in (("volume_shifts.csv", shifts), ("ns_mcmc_comparison.csv", checks)):
        if table:
            with (output / name).open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, fieldnames=list(table[0]))
                writer.writeheader()
                writer.writerows(table)
    (output / "mcmc_status.txt").write_text("\n".join(status) + "\n", encoding="utf-8")
    (output / "comparison_settings.json").write_text(json.dumps({
        "l22_scan": str(l22), "l38_scan": str(l38), "burn_in_MC_steps": burn_in,
        "block_size_measurements": block_size, "mcmc_error": "blocked delete-one-bin jackknife",
        "mcmc_xi_error": "delta method from xi_squared jackknife error",
        "ns_error": "whole-independent-stream bootstrap; same draws across betas",
    }, indent=2), encoding="utf-8")

    panels = [("mean_action_density", r"$\langle\epsilon\rangle$"),
              ("xi_L_over_L", r"$\xi_L/L$"), ("chi_topological", r"$\chi_{\rm top}$"),
              ("mean_G0", r"$G_0$"), ("mean_Gk", r"$G_k$"),
              ("xi_L_squared", r"$\xi_L^2$")]
    fig, axes = plt.subplots(2, 3, figsize=(13, 7.5), constrained_layout=True)
    for ax, (key, label) in zip(axes.flat, panels):
        for method, color in (("NS", "crimson"), ("MCMC", "royalblue")):
            for lattice, marker, style in ((22, "o", "-"), (38, "^", "--")):
                group = [row for row in comparison if row["method"] == method and row["L"] == lattice]
                if not group:
                    continue
                ax.errorbar([row["target_beta"] for row in group], [row[key] for row in group],
                            yerr=[row[f"{key}_se"] for row in group], color=color, marker=marker,
                            markerfacecolor=color if method == "NS" else "white",
                            linestyle=style if method == "NS" else "none", capsize=3,
                            label=f"{method}, L={lattice}")
        ax.set(xlabel=r"$\beta$", ylabel=label, xticks=BETAS)
        ax.grid(alpha=0.2)
    axes[0, 0].legend(fontsize=9)
    fig.suptitle("N=4 volume comparison; NS source beta=0.7\n"
                 "L22: 1500 proposals; L38: 8664 proposals per NS update")
    for suffix in ("png", "pdf"):
        fig.savefig(output / f"volume_dependence.{suffix}", dpi=180)
    plt.close(fig)

    fig, axes = plt.subplots(1, 3, figsize=(13, 3.8), constrained_layout=True)
    for ax, (key, label) in zip(axes, (("last_tenth_target_mass", "Weight in final 10% of common ranks"),
                                       ("stream_weight_ess", "Effective number of weighted streams"),
                                       ("quadrature_ess", "Quadrature ESS (not independent samples)"))):
        for lattice, marker, style in ((22, "o", "-"), (38, "^", "--")):
            group = [row for row in rows if row["method"] == "NS" and row["L"] == lattice]
            ax.plot(BETAS, [row[key] for row in group], color="crimson", marker=marker,
                    linestyle=style, label=f"L={lattice}")
        ax.set(xlabel=r"$\beta$", ylabel=label, xticks=BETAS)
        ax.set_yscale("symlog" if key == "last_tenth_target_mass" else "log", **(
            {"linthresh": 1e-8} if key == "last_tenth_target_mass" else {}))
        ax.grid(alpha=0.2)
    axes[0].legend()
    fig.savefig(output / "coverage_diagnostics.png", dpi=180)
    plt.close(fig)
    print("\n".join(status))
    print(f"Saved volume comparison to {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--l22", required=True, type=Path)
    parser.add_argument("--l38", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mcmc-l22", type=Path)
    parser.add_argument("--mcmc-l38", type=Path)
    parser.add_argument("--mcmc-l22-search", type=Path)
    parser.add_argument("--burn-in", type=int, default=20000)
    parser.add_argument("--block-size", type=int, default=128)
    args = parser.parse_args()
    if args.burn_in < 0 or args.block_size < 1:
        parser.error("require nonnegative burn-in and positive block size")
    try:
        compare(args.l22, args.l38, args.output, args.mcmc_l22, args.mcmc_l38,
                args.mcmc_l22_search, args.burn_in, args.block_size)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
