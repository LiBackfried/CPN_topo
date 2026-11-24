"""Validate a completed UBELIX campaign and report timings by CPU model."""

import argparse
import csv
import json
import math
from pathlib import Path
import re
from statistics import mean, median


def require(condition, message):
    if not condition:
        raise ValueError(message)


def table(path, columns):
    values = [[float(item) for item in line.split()] for line in path.read_text().splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    require(bool(values) and all(len(row) >= columns and all(map(math.isfinite, row))
                                for row in values), f"Invalid table: {path}")
    return values


def metric(text, label):
    found = re.findall(r"^" + re.escape(label) + r"\s*([0-9.eE+-]+) s$", text, re.M)
    require(len(found) == 1, f"Missing or ambiguous timing: {label}")
    value = float(found[0])
    require(math.isfinite(value) and value >= 0, f"Invalid timing: {label}")
    return value


def write_csv(path, rows):
    with path.open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--compare-observables", action="store_true")
    args = parser.parse_args()
    campaign = args.campaign.resolve()
    with (campaign / "jobs.tsv").open(newline="") as file:
        manifest = list(csv.DictReader(file, delimiter="\t"))
    require(len(manifest) == 2 and {int(row["proposals"]) for row in manifest} == {15500, 31000},
            "Expected two proposal-count arms")
    require(len({row["updates"] for row in manifest}) == 1, "Both arms must use the same depth")
    timings, seeds = [], set()
    for job in manifest:
        root = Path(job["job_directory"]).resolve()
        require(root.parent == campaign and root.name == f"job_{job['job_id']}", "Unexpected job directory")
        require((root / "completed").is_file(), f"Job incomplete: {root}")
        require({p.name for p in root.glob("run_*") if p.is_dir()} == {f"run_{i}" for i in range(10)},
                f"Expected ten streams: {root}")
        steps, proposals = int(job["updates"]), int(job["proposals"])
        for index in range(10):
            run = root / f"run_{index}"
            require((run / "completed").is_file(), f"Stream incomplete: {run}")
            config = {}
            for line in (run / "input.conf").read_text().splitlines():
                fields = line.split("#", 1)[0].split()
                if fields:
                    require(fields[0] not in config, f"Duplicate setting: {run}")
                    config[fields[0]] = " ".join(fields[1:])
            seed = int(config["rng_seed"])
            require(seed == int(job["seed_base"]) + index and 0 < seed < 2147483399 and seed not in seeds,
                    f"Incorrect or repeated seed: {run}")
            seeds.add(seed)
            expected = {"size": "72 72", "beta": "0.6", "theta": "0.0", "start": "1", "rng_start": "0",
                        "num_live_pts": "50", "num_ns_meas": str(steps + 1),
                        "num_single_site_stoc_upd": str(proposals), "num_micro": "4", "num_norm": "1",
                        "num_MC_step": "20", "meas_every": "8", "num_cool_step": "50",
                        "meas_cool_every": "5", "save_dead": "0"}
            require(all(config.get(key) == value for key, value in expected.items()), f"Wrong settings: {run}")
            data, acceptance = table(run / "dati.dat", 4), table(run / "acceptance_rate.dat", 4)
            require(len(data) == steps + 1 and len(acceptance) == steps, f"Wrong row count: {run}")
            require(all(a[1] >= b[1] - 1e-12 for a, b in zip(data, data[1:])), f"Cutoff increased: {run}")
            require(all(row[0] == i and 0 <= row[1] <= 1 and 0 <= row[2] <= 1
                        for i, row in enumerate(acceptance, 1)), f"Invalid acceptance: {run}")
            topology = table(run / "topo.dat", 5)
            require(len(topology) == 11 * (steps + 1) and
                    all(row[1] == (i % 11) * 5 for i, row in enumerate(topology)), f"Invalid cooling rows: {run}")
            energies = table(run / "live_energy.dat", 1)
            require(len(energies) == 50 and abs(max(row[0] for row in energies) - data[-1][1]) <= 1e-12,
                    f"Final live-energy table/cutoff mismatch: {run}")
            stdout = (run / "stdout.log").read_text()
            wall = metric(stdout, "#NS loop wall time:")
            cpu = metric(stdout, "#Simulation time:")
            init = metric(stdout, "#Heatbath init. time:")
            require(wall > 0 and cpu > 0, f"Nonpositive loop time: {run}")
            process = dict(line.split("=", 1) for line in (run / "timing.txt").read_text().splitlines())
            elapsed, rss = float(process["elapsed_seconds"]), int(process["max_rss_kib"])
            require(math.isfinite(elapsed) and elapsed > 0 and rss > 0, f"Invalid process metrics: {run}")
            node = (run / "node.txt").read_text().splitlines()
            require(len(node) >= 2 and bool(node[1]), f"Missing CPU model: {run}")
            timings.append(dict(proposals=proposals, updates=steps, job_id=job["job_id"], stream=index,
                seed=seed, node=node[0], cpu_model=node[1], loop_wall_s_per_update=wall / steps,
                loop_cpu_s_per_update=cpu / steps, initialization_cpu_s=init,
                process_wall_s=elapsed, max_rss_kib=rss, initial_cutoff=data[0][1], final_cutoff=data[-1][1],
                mean_z_acceptance=mean(row[1] for row in acceptance),
                mean_u_acceptance=mean(row[2] for row in acceptance)))
    args.output.mkdir(parents=True, exist_ok=True)
    write_csv(args.output / "timings.csv", timings)
    summaries = []
    for proposals, cpu_model in sorted({(row["proposals"], row["cpu_model"]) for row in timings}):
        group = [row for row in timings if (row["proposals"], row["cpu_model"]) == (proposals, cpu_model)]
        wall = [row["loop_wall_s_per_update"] for row in group]
        summaries.append(dict(proposals=proposals, cpu_model=cpu_model, streams=len(group),
            median_wall_s_per_update=median(wall), min_wall_s_per_update=min(wall), max_wall_s_per_update=max(wall),
            median_cpu_s_per_update=median(row["loop_cpu_s_per_update"] for row in group),
            median_initialization_cpu_s=median(row["initialization_cpu_s"] for row in group),
            max_rss_kib=max(row["max_rss_kib"] for row in group)))
    write_csv(args.output / "timing_summary.csv", summaries)
    lines = ["# N=21 L=72 UBELIX benchmark", "",
             "Fresh beta=0.6, theta=0; 50 live points, ten distinct seeds per arm.", "",
             "| Proposals | CPU model | Streams | Median wall s/update | Range | Max RSS MiB |",
             "| ---: | --- | ---: | ---: | --- | ---: |"]
    for row in summaries:
        lines.append(f"| {row['proposals']} | {row['cpu_model']} | {row['streams']} | "
                     f"{row['median_wall_s_per_update']:.6f} | {row['min_wall_s_per_update']:.6f}–"
                     f"{row['max_wall_s_per_update']:.6f} | {row['max_rss_kib']/1024:.1f} |")
    lines += ["", "CPU models are grouped separately. Ranges describe stream variation, not confidence intervals.",
              "Loop timings exclude initialization and the first measurement; process timings include them.",
              "These timings include UBELIX scratch I/O and concurrent streams.",
              "The proposal-count comparison and high acceptance do not establish thermalization or mixing."]
    if args.compare_observables:
        arms = [json.loads((args.output / f"p{p}/results.json").read_text()) for p in (15500, 31000)]
        require(all(arm["settings"]["cpn_n"] == 21 and arm["settings"]["source_beta"] == 0.6 and
                    not arm["settings"]["beta_reweighted"] for arm in arms), "Wrong canonical analysis settings")
        comparison = []
        for key in ("mean_action_density", "mean_G0", "mean_Gk", "xi_L_squared", "mean_Q_U",
                    "mean_Q_U_squared", "chi_topological"):
            a, b = [arm["estimates"][key] for arm in arms]
            ea, eb = [arm["bootstrap_standard_errors"][key] for arm in arms]
            difference, error = b - a, math.hypot(ea, eb)
            ratio = difference / error if error > 0 and all(map(math.isfinite, (difference, error))) else ""
            comparison.append(dict(observable=key, p15500=a, p15500_bootstrap_se=ea, p31000=b,
                                   p31000_bootstrap_se=eb, difference=difference, combined_se=error,
                                   difference_over_combined_se=ratio))
        write_csv(args.output / "observable_comparison.csv", comparison)
        lines += ["", "Separate weighted analyses use 500 whole-stream bootstrap replicates per arm.",
                  "observable_comparison.csv reports differences divided by combined standard errors.",
                  "These are descriptive marginal comparisons, not a joint test or a comparison with direct MCMC."]
    (args.output / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
