#!/usr/bin/env python3
"""Compare locally available N=4 volume summaries without filling missing betas."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from itertools import combinations
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parents[1]
BETAS = (0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0)
QUANTITIES = ("mean_action_density", "chi_topological", "xi_L_squared", "xi_L",
              "xi_L_over_L", "mean_G0", "mean_Gk")
PROPOSALS = {22: 1500, 38: 8664, 66: 26136}


def read_csv(path):
    with path.open(newline="", encoding="utf-8-sig") as file:
        return list(csv.DictReader(file))


def number(row, key, default=np.nan):
    value = row.get(key, "")
    return float(value) if value != "" else default


def add_correlation_length(row):
    # Saved depth CSVs do not contain xi bootstrap replicates. Use the same
    # explicit first-order propagation for every volume and MCMC reference.
    value, error = row["xi_L_squared"], row["xi_L_squared_se"]
    valid = np.isfinite(value) and value > 0
    row["xi_L"] = np.sqrt(value) if valid else np.nan
    row["xi_L_se"] = error / (2 * row["xi_L"]) if valid else np.nan
    row["xi_L_over_L"] = row["xi_L"] / row["L"]
    row["xi_L_over_L_se"] = row["xi_L_se"] / row["L"]
    row["xi_status"] = "unresolved" if not valid or value <= error else "resolved_at_one_SE"
    row["xi_error_method"] = "delta_method_from_xi_squared_SE"
    return row


def ns_from_summary(path, lattice):
    selected = {}
    for raw in read_csv(path):
        if int(float(raw["L"])) != lattice:
            raise ValueError(f"Expected L={lattice} in {path}")
        beta = float(raw["target_beta"])
        if beta not in BETAS:
            continue
        if "stochastic_proposals" in raw and int(float(raw["stochastic_proposals"])) != PROPOSALS[lattice]:
            raise ValueError(f"Unexpected proposal count in {path}")
        if beta not in selected or number(raw, "updates") > number(selected[beta], "updates"):
            selected[beta] = raw
        elif number(raw, "updates") == number(selected[beta], "updates"):
            raise ValueError(f"Duplicate beta/depth in {path}: {beta}")
    if not selected:
        raise ValueError(f"No requested beta points in {path}")
    rows = []
    for beta, raw in sorted(selected.items()):
        row = {"method": "NS", "L": lattice, "target_beta": beta,
               "chains": int(float(raw["chains"])), "updates": int(float(raw["updates"])),
               "stochastic_proposals": PROPOSALS[lattice], "input_file": str(path.resolve()),
               "source_beta": 0.7, "error_method": "whole_independent_stream_bootstrap"}
        for key in ("mean_action_density", "chi_topological", "xi_L_squared", "mean_G0", "mean_Gk"):
            row[key] = number(raw, key)
            row[f"{key}_se"] = number(raw, f"{key}_bootstrap_se")
            if not np.isfinite(row[key]) or not np.isfinite(row[f"{key}_se"]) or row[f"{key}_se"] < 0:
                raise ValueError(f"Missing/invalid {key} or error for L={lattice}, beta={beta}")
        for key in ("last_tenth_target_mass", "stream_weight_ess", "quadrature_ess",
                    "log_missing_target_fraction_bound", "common_epsilon_edge"):
            row[key] = number(raw, key)
        row["xi_bootstrap_finite_fraction"] = number(raw, "xi_L_bootstrap_finite_fraction")
        row["edge_status"] = "edge_mass_above_1_percent" if row["last_tenth_target_mass"] > 0.01 else "edge_screen_pass"
        rows.append(add_correlation_length(row))
    return rows


def mc_from_binning(path, lattice, beta, block_size=128):
    selected = [raw for raw in read_csv(path) if raw["chain"] == "pooled"
                and int(raw["block_size_measurements"]) == block_size]
    values = {raw["observable"]: raw for raw in selected}
    row = {"method": "MCMC", "L": lattice, "target_beta": beta, "chains": 3,
           "burn_in_MC_steps": 20000, "block_size_measurements": block_size,
           "input_file": str(path.resolve()), "error_method": "blocked_delete_one_bin_jackknife"}
    for key in ("mean_action_density", "chi_topological", "xi_L_squared", "mean_G0", "mean_Gk"):
        if key not in values:
            raise ValueError(f"No pooled {key} at block size {block_size} in {path}")
        row[key] = number(values[key], "estimate")
        row[f"{key}_se"] = number(values[key], "standard_error")
    return add_correlation_length(row)


def write_csv(path, rows):
    if not rows:
        raise ValueError(f"No rows to write to {path}")
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def difference(first, second, key):
    error = np.hypot(first[f"{key}_se"], second[f"{key}_se"])
    delta = first[key] - second[key]
    return {"difference": delta, "difference_se": error,
            "difference_in_standard_errors": delta / error if error > 0 else np.nan}


def tables(rows, references, output):
    ns = [row for row in rows if row["method"] == "NS"]
    write_csv(output / "volume_comparison.csv", rows)
    available = []
    for lattice in (22, 38, 66):
        for beta in BETAS:
            point = next((r for r in ns if (r["L"], r["target_beta"]) == (lattice, beta)), None)
            available.append({"L": lattice, "target_beta": beta,
                              "status": "available" if point else "missing_local_summary",
                              "xi_status": point["xi_status"] if point else "unavailable"})
    write_csv(output / "availability.csv", available)
    shifts = []
    for small, large in combinations((22, 38, 66), 2):
        for beta in BETAS:
            pair = [next((r for r in ns if (r["L"], r["target_beta"]) == (l, beta)), None)
                    for l in (small, large)]
            if any(r is None for r in pair):
                continue
            for key in QUANTITIES:
                shifts.append({"L_small": small, "L_large": large, "target_beta": beta,
                               "observable": key, "small": pair[0][key], "large": pair[1][key],
                               "edge_screen_pass": all(r["edge_status"] == "edge_screen_pass" for r in pair),
                               **difference(pair[1], pair[0], key)})
    write_csv(output / "volume_shifts.csv", shifts)
    checks = []
    for mc in (r for r in rows if r["method"] == "MCMC"):
        point = next(r for r in ns if (r["L"], r["target_beta"]) == (mc["L"], mc["target_beta"]))
        for key in QUANTITIES:
            checks.append({"L": mc["L"], "target_beta": mc["target_beta"], "observable": key,
                           "NS": point[key], "NS_se": point[f"{key}_se"],
                           "MCMC": mc[key], "MCMC_se": mc[f"{key}_se"], **difference(point, mc, key)})
    write_csv(output / "ns_mcmc_comparison.csv", checks)
    matches = []
    for ref in references:
        lattice, beta = int(ref["L"]), float(ref["beta"])
        for point in rows:
            if point["L"] != lattice or not np.isclose(point["target_beta"], beta):
                continue
            error = np.hypot(point["xi_L_se"], float(ref["xi_L_error"]))
            matches.append({"L": lattice, "target_beta": beta, "method": point["method"],
                            "xi_L": point["xi_L"], "xi_L_se": point["xi_L_se"],
                            "table_xi_L": float(ref["xi_L"]), "table_xi_L_se": float(ref["xi_L_error"]),
                            "difference_in_standard_errors": (point["xi_L"] - float(ref["xi_L"])) / error})
    write_csv(output / "matched_table_checks.csv", matches)
    return shifts, matches


def plot(rows, references, output):
    panels = (("mean_action_density", r"$\langle\epsilon\rangle$"),
              ("xi_L_over_L", r"$\xi_L/L$"), ("chi_topological", r"$\chi_{\rm top}$"),
              ("mean_G0", r"$G_0$"), ("mean_Gk", r"$G_k$"), ("xi_L_squared", r"$\xi_L^2$"))
    fig, axes = plt.subplots(2, 3, figsize=(14, 8.5))
    for ax, (key, label) in zip(axes.flat, panels):
        for method, color in (("NS", "crimson"), ("MCMC", "royalblue")):
            for lattice, marker, style in ((22, "o", "-"), (38, "^", "--"), (66, "s", ":")):
                group = {r["target_beta"]: r for r in rows if (r["L"], r["method"]) == (lattice, method)}
                if not group:
                    continue
                y = [group[b][key] if b in group else np.nan for b in BETAS]
                err = [group[b][f"{key}_se"] if b in group else np.nan for b in BETAS]
                ax.errorbar(BETAS, y, yerr=err, color=color, marker=marker,
                            markerfacecolor=color if method == "NS" else "white",
                            linestyle=style if method == "NS" else "none", capsize=3,
                            label=f"{method}, L={lattice}")
                if key == "xi_L_over_L" and method == "NS":
                    for beta, row in group.items():
                        if row["xi_status"] == "unresolved":
                            ax.text(beta, 0.04, "?", transform=ax.get_xaxis_transform(), ha="center",
                                    va="bottom", color=color, fontsize=13, fontweight="bold")
        if key == "xi_L_squared":
            ax.axhline(0, color="0.5", lw=0.7)
        ax.set(xlabel=r"$\beta$", ylabel=label, xticks=BETAS)
        ax.grid(alpha=0.18)
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=5, bbox_to_anchor=(0.5, 0.94), frameon=False)
    counts = {r["L"]: r["chains"] for r in rows if r["method"] == "NS"}
    fig.suptitle("N=4 volume comparison, NS source beta=0.7\n"
                 f"L22: {counts[22]} streams / 1500 proposals; L38: {counts[38]} / 8664; L66: {counts[66]} / 26136", y=0.995)
    fig.text(0.5, 0.015, "Missing L38 betas are left as gaps.  ? = unresolved L66 correlation length.  Errors are statistical only.",
             ha="center", fontsize=10)
    fig.tight_layout(rect=(0, 0.04, 1, 0.88))
    for suffix in ("png", "pdf"):
        fig.savefig(output / f"volume_dependence.{suffix}", dpi=180)
    plt.close(fig)

    fig, axes = plt.subplots(1, 3, figsize=(14, 4.5), constrained_layout=True)
    diagnostics = (("last_tenth_target_mass", "Weight in final 10% of ranks"),
                   ("stream_weight_ess", "Stream-weight ESS"),
                   ("quadrature_ess", "Quadrature ESS (not independent samples)"))
    for ax, (key, label) in zip(axes, diagnostics):
        for lattice, marker, style in ((22, "o", "-"), (38, "^", "--"), (66, "s", ":")):
            group = {r["target_beta"]: r for r in rows if r["method"] == "NS" and r["L"] == lattice}
            ax.plot(BETAS, [group[b][key] if b in group else np.nan for b in BETAS],
                    color="crimson", marker=marker, linestyle=style, label=f"L={lattice}")
        ax.set(xlabel=r"$\beta$", ylabel=label, xticks=BETAS)
        ax.set_yscale("symlog" if key == "last_tenth_target_mass" else "log",
                      **({"linthresh": 1e-8} if key == "last_tenth_target_mass" else {}))
        if key == "last_tenth_target_mass":
            ax.axhline(0.01, color="0.5", linestyle="--", label="1% screen")
        ax.grid(alpha=0.18)
    axes[0].legend(fontsize=9)
    fig.savefig(output / "coverage_diagnostics.png", dpi=180)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(7.5, 5), constrained_layout=True)
    matched = [ref for ref in references if any(r["method"] == "NS" and r["L"] == int(ref["L"])
               and r["target_beta"] == float(ref["beta"]) for r in rows)]
    for method, color, offset in (("Table III", "0.3", -0.12), ("NS", "crimson", 0),
                                  ("MCMC", "royalblue", 0.12)):
        for i, ref in enumerate(matched):
            if method == "Table III":
                value, error = float(ref["xi_L"]), float(ref["xi_L_error"])
            else:
                point = next((r for r in rows if r["method"] == method and r["L"] == int(ref["L"])
                              and r["target_beta"] == float(ref["beta"])), None)
                if point is None:
                    continue
                value, error = point["xi_L"], point["xi_L_se"]
            ax.errorbar(i + offset, value, yerr=error, color=color, marker="o",
                        markerfacecolor="white" if method == "MCMC" else color,
                        capsize=4, label=method)
    handles, labels = ax.get_legend_handles_labels()
    unique = dict(zip(labels, handles))
    ax.legend(unique.values(), unique.keys(), frameon=False)
    ax.set(xticks=range(len(matched)),
           xticklabels=[f"β={float(r['beta']):.2f}\nL={r['L']}" for r in matched],
           ylabel=r"$\xi_L$", title="Table III checks at matching beta and volume")
    ax.grid(axis="y", alpha=0.2)
    for suffix in ("png", "pdf"):
        fig.savefig(output / f"matched_table_comparison.{suffix}", dpi=180)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "N4_L66_res/volume_comparison_local")
    parser.add_argument("--l22-scan", type=Path)
    parser.add_argument("--l38-depth", type=Path, default=REPO / "N4_L38_res/extra8664.m3YXfE/depth_combined24.csv")
    parser.add_argument("--l66-depth", type=Path, default=REPO / "N4_L66_res/comparison_22587511/depth.csv")
    parser.add_argument("--mcmc-l38-binning", type=Path, default=REPO / "N4_L38_res/extra8664.m3YXfE/mcmc_burn20000/binning.csv")
    parser.add_argument("--mcmc-l66-binning", type=Path, default=REPO / "N4_L66_res/comparison_22587511/mcmc_burn20000/binning.csv")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    l22 = args.l22_scan or args.output / "L22/beta_scan.csv"
    inputs = (l22, args.l38_depth, args.l66_depth, args.mcmc_l38_binning,
              args.mcmc_l66_binning, REPO / "N4_L66_res/reference_targets.csv")
    rows = sum((ns_from_summary(path, lattice) for path, lattice in zip(inputs[:3], (22, 38, 66))), [])
    rows += [mc_from_binning(inputs[3], 38, 1.0), mc_from_binning(inputs[4], 66, 0.9)]
    references = read_csv(inputs[5])
    tables(rows, references, args.output)
    plot(rows, references, args.output)
    provenance = {"inputs": [{"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                             for path in inputs],
                  "missing_L38_betas": [b for b in BETAS if not any(r["method"] == "NS" and r["L"] == 38 and r["target_beta"] == b for r in rows)],
                  "NS_errors": "whole-stream bootstrap; L22 regenerated from local 25-stream subset",
                  "MCMC_errors": "saved pooled jackknife, burn-in 20000 MC steps, bins of 128 measurements",
                  "xi_errors": "first-order propagation of xi_squared SE for all methods/volumes",
                  "proposal_counts": PROPOSALS,
                  "limitations": ["No interpolation or invented bootstrap replicates for missing summaries",
                                  "Different NS proposal counts and sample sizes across volumes",
                                  "Finite depth and constrained-chain mixing bias excluded from errors"]}
    (args.output / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    (args.output / "README.md").write_text(
        "# Local L22/L38/L66 comparison\n\n"
        "This comparison uses 25 local L22 streams (runs 750–774), the saved "
        "24-stream L38 ensemble at 8,664 proposals/update, and 12 L66 streams "
        "at 26,136 proposals/update. L22 uses 1,500 proposals/update. "
        "All simulations have N=4, source beta=0.7 and theta=0.\n\n"
        "The L22 grid was regenerated locally with 200 whole-stream bootstrap "
        "replicates, seed 20261118. It is a subset, not the 100-stream UBELIX "
        "scan or the 800-stream production estimate. Its exact inputs and "
        "settings are in L22/inputs.json and L22/selected_runs.txt.\n\n"
        "L38 summaries are available only at beta=0.8, 0.9 and 1.0. "
        "The four other L38 betas are missing and remain gaps; no interpolation "
        "was performed. L66 covers all seven betas from 0.7 to 1.0.\n\n"
        "Direct MCMC references are included only at their simulated points: "
        "L38 at beta=1.0 (job 22121710) and L66 at beta=0.9 (job 22587511). "
        "Both use the saved pooled jackknife with a 20,000-MC-step burn-in cut "
        "and blocks of 128 measurements. No L22 production MCMC reference "
        "is available locally.\n\n"
        "All xi and xi/L errors use first-order propagation of xi-squared "
        "errors, for consistency with saved depth summaries that lack raw "
        "xi bootstrap samples. Negative xi-squared estimates are preserved. "
        "Their square roots and propagated errors remain NaN, and question "
        "marks flag the unresolved L66 points in the xi/L panel. This "
        "propagation is not a bootstrap interval for xi.\n\n"
        "## Outputs\n\n"
        "- volume_dependence.png and .pdf: six observable panels. NS is "
        "crimson; MCMC is royalblue. Markers distinguish volumes.\n"
        "- coverage_diagnostics.png: edge weight, stream-weight ESS and "
        "quadrature ESS (not independent sample counts).\n"
        "- matched_table_comparison.png and .pdf: only matching-volume, "
        "matching-beta checks against the supplied Table III.\n"
        "- volume_comparison.csv: all available estimates, errors and provenance.\n"
        "- volume_shifts.csv: larger minus smaller volume at common available "
        "betas, with independent-volume errors added in quadrature.\n"
        "- ns_mcmc_comparison.csv: same-volume, same-beta NS/MCMC checks.\n"
        "- matched_table_checks.csv: table comparisons with combined errors.\n"
        "- availability.csv: all 21 volume/beta combinations, including gaps.\n"
        "- provenance.json: exact source paths, SHA256 hashes and methods.\n\n"
        "Errors are statistical. Different proposal counts and initialization "
        "or constrained-chain mixing biases can affect comparisons; a volume "
        "shift alone does not establish its physical origin. Edge weight below "
        "1% is a screen, not proof of complete target coverage. A bound of zero "
        "in log_missing_target_fraction_bound is uninformative.\n\n"
        "## Reproduce from the repository root\n\n"
        "Use the fpaction2 Conda environment locally. To rebuild the L22 scan:\n\n"
        "```bash\npython N4_volume_benchmark/scan_volume_betas.py ../data_N4_UBELIX "
        "--output N4_L66_res/volume_comparison_local/L22 --bootstrap 200 --seed 20261118 "
        "--expected-lattice 22 --expected-stoc 1500 --expected-chains 25\n```\n\n"
        "To regenerate comparison tables and figures from saved summaries:\n\n"
        "```bash\npython N4_volume_benchmark/compare_saved_volumes.py\n```\n",
        encoding="utf-8")
    print(f"Saved {len(rows)} points to {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        sys.exit(str(exc))
