"""Summarize the local timings and verify overlap with historical trajectories."""

import argparse
import csv
import json
from pathlib import Path
from statistics import mean, median


REPO = Path(__file__).resolve().parent.parent


def read_csv(path):
    with path.open(newline="") as file:
        return list(csv.DictReader(file))


def rows(path):
    return [[float(value) for value in line.split()] for line in path.read_text().splitlines()
            if line.strip() and not line.startswith("#")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    timings = read_csv(args.results / "timings.csv")
    assert len(timings) == 12
    historical = REPO / "N21_L72_benchmark_20261116/results"
    previous = read_csv(historical / "timings.csv")
    summary = {}
    for mode, lattice, proposals in (("resume", 72, 5000), ("fresh", 72, 5000),
                                     ("fresh", 72, 15500), ("fresh", 150, 67500)):
        group = [row for row in timings if (row["mode"], int(row["lattice"]),
                 int(row["proposals"])) == (mode, lattice, proposals)]
        assert len(group) == 3
        assert len({row["input_seed"] for row in group}) == 3
        assert all(int(row["updates"]) == 100 for row in group)
        wall = [float(row["loop_wall_s_per_update"]) for row in group]
        cpu = [float(row["loop_cpu_s"]) / int(row["updates"]) for row in group]
        result = dict(median_loop_wall_s_per_update=median(wall), wall_range=[min(wall), max(wall)],
                      median_loop_cpu_s_per_update=median(cpu),
                      median_initialization_cpu_s=median(float(row["initialization_cpu_s"]) for row in group),
                      median_process_wall_s=median(float(row["process_wall_s"]) for row in group),
                      loop_minutes_per_10000_updates=median(wall) * 10000 / 60,
                      max_checkpoint_energy_error=max(float(row["final_checkpoint_max_energy_error"])
                                                      for row in group))
        if lattice == 72 and proposals == 5000:
            speedups, cpu_speedups, energy_differences, acceptance_differences = [], [], [], []
            for current in group:
                old = next(row for row in previous if row["mode"] == mode and row["variant"] == "baseline"
                           and row["input_seed"] == current["input_seed"])
                speedups.append(float(old["loop_wall_s_per_update"]) / float(current["loop_wall_s_per_update"]))
                cpu_speedups.append((float(old["loop_cpu_s"]) / int(old["updates"])) /
                                   (float(current["loop_cpu_s"]) / int(current["updates"])))
                before = historical / f"{mode}_run_{old['stream']}_baseline"
                after = args.results / f"{mode}_run_{current['stream']}_updated"
                energy_differences.extend(abs(a[1] - b[1]) for a, b in
                                          zip(rows(before / "dati.dat"), rows(after / "dati.dat")))
                acceptance_differences.extend(abs(a[col] - b[col]) for a, b in
                    zip(rows(before / "acceptance_rate.dat"), rows(after / "acceptance_rate.dat"))
                    for col in (1, 2))
            assert max(energy_differences) < 1e-9 and max(acceptance_differences) == 0
            result.update(median_seed_matched_historical_wall_speedup=median(speedups),
                          median_seed_matched_historical_cpu_speedup=median(cpu_speedups),
                          historical_max_cutoff_difference=max(energy_differences),
                          historical_max_acceptance_difference=max(acceptance_differences))
        if lattice == 72 and proposals == 15500:
            old = read_csv(REPO / "N4_L22_runs/smoke_runtime_20261020/benchmark_summary.csv")
            old_cpu = mean(float(row["simulation_seconds_per_ns_update"]) for row in old if row["N"] == "21")
            result.update(historical_mean_cpu_s_per_update=old_cpu,
                          historical_cpu_speedup=old_cpu / median(cpu))
            old_acc = rows(REPO / "N4_L22_runs/smoke_runtime_20261020/results_N21_L72/acceptance_rate.dat")
            new_acc = rows(args.results / "fresh_run_L72_p15500_seed46774_updated/acceptance_rate.dat")
            difference = max(abs(a[col] - b[col]) for a, b in zip(old_acc, new_acc) for col in (1, 2))
            assert difference == 0
            result["historical_max_acceptance_difference"] = difference
        summary[f"{mode}_L{lattice}_p{proposals}"] = result
    (args.results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
