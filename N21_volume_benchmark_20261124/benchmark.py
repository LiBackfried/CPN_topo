"""Benchmark current N=21 NS code under Ubuntu-24.04 WSL, using private copies.

Reuse the November 16 timing probe, checkpoint audit, and output validation.
Only committed simulation sources are built; uncommitted source changes abort.
"""

import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "previous_benchmark", REPO / "N21_L72_benchmark_20261116/benchmark.py")
pilot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pilot)


def trial_input(source, resume, updates):
    parameters = dict(line.split(maxsplit=1) for line in
                      (source / "input.conf").read_text().splitlines()
                      if line.strip() and not line.lstrip().startswith("#"))
    assert parameters["num_live_pts"] == "50"
    assert parameters["beta"] == "0.6" and parameters["theta"] == "0.0"
    parameters.update(start="2" if resume else "1", rng_start="1" if resume else "0",
                      num_ns_meas=str(updates + 1))
    return "".join(f"{key} {value}\n" for key, value in parameters.items()), parameters["rng_seed"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cpu", type=int, default=8)
    parser.add_argument("--updates", type=int, default=100)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or args.updates < 1:
        parser.error("Choose an available CPU and positive update count")
    if subprocess.run(["git", "diff", "--quiet", "--ignore-space-at-eol", "HEAD", "--",
                       *pilot.BUILD_FILES], cwd=REPO).returncode:
        parser.error("Commit simulation source changes before benchmarking")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    pilot.REVISIONS["updated"] = revision
    pilot.trial_input = trial_input
    output = args.output.resolve()
    output.mkdir()
    with tempfile.TemporaryDirectory(prefix="cpn_n21_volumes_", dir="/tmp") as temporary:
        root = Path(temporary)
        executable, md5_enabled = pilot.build(root, "updated", output)
        checker_source = root / "updated/src/checkpoint_energies.c"
        shutil.copyfile(REPO / "N21_L72_benchmark_20261116/checkpoint_energies.c", checker_source)
        checker = root / "updated/checkpoint_energies"
        with (output / "checker_build.log").open("w") as log:
            subprocess.run(["gcc", "-std=c99", "-O3", "-o", checker,
                            checker_source, *sorted((root / "updated/lib").glob("*.o")), "-lm"],
                           cwd=root / "updated", stdout=log, stderr=subprocess.STDOUT, check=True)
        with (output / "environment.txt").open("w") as log:
            for command in (["uname", "-sr"], ["gcc", "--version"], ["lscpu"],
                            ["findmnt", "-T", temporary, "-n", "-o", "FSTYPE"]):
                subprocess.run(command, stdout=log, check=True)
            log.write(f"Pinned logical CPU: {args.cpu}\nConfiguration MD5 enabled: {md5_enabled}\n")
        (output / "provenance.json").write_text(json.dumps({
            "revision": revision, "compiled_N": 21, "cpu": args.cpu, "updates": args.updates,
            "source_matches_previous_optimized_build": not bool(subprocess.check_output(
                ["git", "diff", "37d1e55", revision, "--", *pilot.BUILD_FILES], cwd=REPO)),
            "timing": "CLOCK_MONOTONIC NS-loop wall time; separate process wall and loop CPU time",
            "filesystem": "WSL ext4 scratch; output copy excluded from timing",
            "md5_enabled": md5_enabled,
        }, indent=2) + "\n")
        selected = pilot.select_checkpoints(checker, output)
        checkpoints = {number: pilot.prepare_checkpoint(root, output, executable, checker,
                                                        args.cpu, number, repair)
                       for repair, number in selected}
        with (output / "timings.csv").open("w", newline="") as csv_file:
            writer = None
            for mode, lattice, proposals, seeds in (
                ("resume", 72, 5000, (16774, 16775, 16776)),
                ("fresh", 72, 5000, (16774, 16775, 16776)),
                ("fresh", 72, 15500, (46774, 46775, 46776)),
                ("fresh", 150, 67500, (46774, 46775, 46776)),
            ):
                for index, seed in enumerate(seeds):
                    if mode == "resume":
                        source = checkpoints[index]
                    else:
                        source = root / f"template_L{lattice}_p{proposals}_s{seed}"
                        source.mkdir()
                        config, _ = trial_input(REPO / "out_data_ubelix/run_0", False, args.updates)
                        parameters = dict(line.split(maxsplit=1) for line in config.splitlines())
                        parameters.update(size=f"{lattice} {lattice}", rng_seed=str(seed),
                                          num_single_site_stoc_upd=str(proposals))
                        (source / "input.conf").write_text("".join(
                            f"{key} {value}\n" for key, value in parameters.items()))
                    label = f"L{lattice}_p{proposals}_seed{seed}"
                    row = pilot.run_trial(root, output, executable, args.cpu, mode, label,
                                          "updated", args.updates, source)
                    row.update(lattice=lattice, proposals=proposals)
                    # Verify the final private checkpoint as well as the output rows.
                    scratch = root / f"{mode}_run_{label}_updated"
                    _, errors = pilot.compare_live_energies(checker, scratch)
                    assert max(errors) <= 1e-12
                    row["final_checkpoint_max_energy_error"] = max(errors)
                    if writer is None:
                        writer = csv.DictWriter(csv_file, fieldnames=row.keys())
                        writer.writeheader()
                    writer.writerow(row)
                    csv_file.flush()
                    # Large checkpoint copies are transient; retain small raw outputs.
                    shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
