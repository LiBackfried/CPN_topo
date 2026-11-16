"""Run the matched N=21, L=72 timing pilot from Ubuntu-24.04 WSL."""

import argparse
import csv
import math
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from array import array
from hashlib import md5, sha256
from io import BytesIO
from pathlib import Path
from statistics import mean


REPO = Path(__file__).resolve().parent.parent
REVISIONS = {
    "baseline": "5428e2b04fd79428ae33a8d0e9091a2675f79976",
    "updated": "37d1e552aedad80e8a06d86193677714208d71eb",
}
BUILD_FILES = ("src", "lib", "include", "Makefile.am", "configure.ac", "script_build_code.sh")
CHECKPOINT_FILES = [f"conf.dat_live_{index}" for index in range(50)] + [
    "live_energy.dat", "rng_state.dat"
]
RESULT_FILES = ("dati.dat", "topo.dat", "acceptance_rate.dat", "live_energy.dat", "log.dat")


def build(root, variant, result_dir):
    directory = root / variant
    directory.mkdir()
    archive = subprocess.check_output(["git", "archive", REVISIONS[variant], *BUILD_FILES], cwd=REPO)
    with tarfile.open(fileobj=BytesIO(archive)) as files:
        files.extractall(directory, filter="data")

    header = directory / "include/macro.h"
    source = header.read_text()
    source, count = re.subn(r"^#define N \d+$", "#define N 21", source, flags=re.MULTILINE)
    assert count == 1
    header.write_text(source)

    # Identical loop-boundary instrumentation in the two source snapshots.
    main = directory / "src/cpn_ns.c"
    source = main.read_text()
    start = "\n\tstart_time=clock();\n"
    finish = "\n\tfinish_time=clock();\n"
    assert source.count(start) == 1 and source.count(finish) == 1
    source = source.replace(start, start + "\tstruct timespec wall_start, wall_finish;\n"
                            "\tclock_gettime(CLOCK_MONOTONIC, &wall_start);\n")
    source = source.replace(finish, "\n\tclock_gettime(CLOCK_MONOTONIC, &wall_finish);\n" + finish
                            + '\tfprintf(stdout, "#NS loop wall time: %.9f s\\n",\n'
                            "\t        (double)(wall_finish.tv_sec - wall_start.tv_sec) +\n"
                            "\t        1e-9 * (double)(wall_finish.tv_nsec - wall_start.tv_nsec));\n")
    main.write_text(source)

    with (result_dir / f"{variant}_build.log").open("w") as log:
        for command in (["bash", "script_build_code.sh"],
                        ["./configure", "CC=gcc", "CFLAGS=", "ac_cv_header_openssl_md5_h=no"],
                        ["make", "-j4", "cpn_ns"]):
            subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT, check=True)
        if variant == "baseline":
            shutil.copyfile(Path(__file__).with_name("checkpoint_energies.c"),
                            directory / "src/checkpoint_energies.c")
            objects = sorted((directory / "lib").glob("*.o"))
            subprocess.run(["gcc", "-std=c99", "-O3", "-o", "checkpoint_energies",
                            "src/checkpoint_energies.c", *objects, "-lm"], cwd=directory,
                           stdout=log, stderr=subprocess.STDOUT, check=True)

    executable = directory / "cpn_ns"
    banner = subprocess.run([executable], capture_output=True, text=True).stdout
    assert "Compiled with N = 21" in banner
    (result_dir / f"{variant}_banner.txt").write_text(banner)
    md5_enabled = "#define ENABLE_MD5_HASH" in (directory / "config.h").read_text()
    return executable, md5_enabled


def data_rows(path):
    return [line.split() for line in path.read_text().splitlines() if line and not line.startswith("#")]


def compare_live_energies(checker, source):
    recorded = [float(row[0]) for row in data_rows(source / "live_energy.dat")]
    computed = [float(value) for value in subprocess.check_output(
        [checker, "input.conf"], cwd=source, text=True).split()]
    assert len(recorded) == len(computed) == 50 and all(map(math.isfinite, recorded + computed))
    return recorded, [abs(actual - stored) for actual, stored in zip(computed, recorded)]


def select_checkpoints(checker, result_dir):
    usable = []
    with (result_dir / "checkpoint_audit.csv").open("w", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(["stream", "rng_seed", "last_saved_ns_label", "max_energy_error",
                         "inconsistent_slots", "maximum_energy_slot", "duplicate_of", "preflight"])
        for number in range(10):
            source = REPO / "out_data_ubelix" / f"run_{number}"
            fingerprints = []
            for filename in CHECKPOINT_FILES[:-2]:
                with (source / filename).open("rb") as config:
                    header_line = config.readline()
                    payload = config.read()
                header = header_line.split()
                assert header[1:4] == [b"21", b"72", b"72"] and len(payload) == 72 * 72 * 23 * 16
                doubles = array("d")
                doubles.frombytes(payload)
                doubles.byteswap()  # Disk payload is big-endian, the stored hash is little-endian.
                assert md5(doubles).hexdigest().encode() == header[4], (number, filename)
                fingerprints.append(sha256(header_line + payload).digest())

            recorded, errors = compare_live_energies(checker, source)
            mismatches = [slot for slot, error in enumerate(errors) if error > 1e-12]
            dead = recorded.index(max(recorded))
            duplicates = [slot for slot, digest in enumerate(fingerprints)
                          if slot != dead and digest == fingerprints[dead]]
            status = "skip"
            if not mismatches:
                status = "consistent"
                usable.append((False, number))
            elif mismatches == [dead] and duplicates:
                # The old loop first wrote a proposal copy into the dead slot. The slot
                # is excluded from proposal selection and replaced in the first update.
                assert recorded.count(recorded[dead]) == 1
                status = "replace dead slot"
                usable.append((True, number))
            seed = (source / "rng_state.dat").read_text().split()[0]
            last_label = data_rows(source / "acceptance_rate.dat")[-1][0]
            writer.writerow([number, seed, last_label, max(errors), " ".join(map(str, mismatches)),
                             dead, " ".join(map(str, duplicates)), status])
            output.flush()
    assert len(usable) >= 3, f"Only found {len(usable)} usable checkpoints"
    return sorted(usable)[:3]


def trial_input(source, resume, updates):
    config = (source / "input.conf").read_text()
    parameters = dict(line.split(maxsplit=1) for line in config.splitlines()
                      if line.strip() and not line.lstrip().startswith("#"))
    expected = {"size": "72 72", "beta": "0.6", "theta": "0.0", "num_live_pts": "50",
                "num_single_site_stoc_upd": "5000", "num_micro": "4", "num_norm": "1",
                "num_cool_step": "50", "meas_cool_every": "5", "num_MC_step": "20",
                "meas_every": "8", "save_dead": "0"}
    assert all(parameters.get(key) == value for key, value in expected.items())
    parameters.update(start="2" if resume else "1", rng_start="1" if resume else "0",
                      num_ns_meas=str(updates + 1))
    return "".join(f"{key} {value}\n" for key, value in parameters.items()), parameters["rng_seed"]


def copy_checkpoint(source, target):
    for filename in CHECKPOINT_FILES:
        shutil.copyfile(source / filename, target / filename)


def prepare_checkpoint(root, result_dir, executable, checker, cpu, number, replace_dead):
    source = REPO / "out_data_ubelix" / f"run_{number}"
    if not replace_dead:
        return source

    work = root / f"prepared_run_{number}"
    work.mkdir()
    output = result_dir / work.name
    output.mkdir()
    copy_checkpoint(source, work)
    config, _ = trial_input(source, resume=True, updates=1)
    (work / "input.conf").write_text(config)
    print(f"Preparing run_{number}: replacing the dead slot in one untimed NS update", flush=True)
    with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
        subprocess.run(["taskset", "-c", str(cpu), executable, "input.conf"],
                       cwd=work, stdout=stdout, stderr=stderr, check=True)

    recorded, errors = compare_live_energies(checker, work)
    input_energies = [float(row[0]) for row in data_rows(source / "live_energy.dat")]
    dead = input_energies.index(max(input_energies))
    assert max(errors) <= 1e-12
    assert recorded[dead] < input_energies[dead] - 1e-9
    assert [index for index in range(50) if recorded[index] != input_energies[index]] == [dead]
    (output / "verification.txt").write_text(
        f"Replaced slot {dead}. Maximum stored-vs-recomputed error: {max(errors):.17g}\n"
        f"Maximum energy before: {max(input_energies):.17g}\nMaximum after: {max(recorded):.17g}\n")
    for filename in ("input.conf", *RESULT_FILES):
        shutil.copyfile(work / filename, output / filename)
    return work


def run_trial(root, result_dir, executable, cpu, mode, number, variant, updates, source):
    name = f"{mode}_run_{number}_{variant}"
    scratch = root / name
    scratch.mkdir()
    output = result_dir / name
    output.mkdir()
    config, seed = trial_input(source, resume=mode == "resume", updates=updates)
    (scratch / "input.conf").write_text(config)
    (output / "input.conf").write_text(config)

    if mode == "resume":
        copy_checkpoint(source, scratch)
        initial_energies = data_rows(scratch / "live_energy.dat")
        assert len(initial_energies) == 50
        shutil.copyfile(scratch / "live_energy.dat", output / "initial_live_energy.dat")

    print(f"Running {name} ({updates} updates)", flush=True)
    with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
        start = time.perf_counter()
        run = subprocess.run(["taskset", "-c", str(cpu), executable, "input.conf"],
                             cwd=scratch, stdout=stdout, stderr=stderr)
        elapsed = time.perf_counter() - start
    for filename in RESULT_FILES:
        if (scratch / filename).is_file():
            shutil.copyfile(scratch / filename, output / filename)
    run.check_returncode()

    stdout = (output / "stdout.log").read_text()
    wall = float(re.search(r"#NS loop wall time: (\S+) s", stdout)[1])
    cpu_time = float(re.search(r"#Simulation time: (\S+) s", stdout)[1])
    init_cpu = float(re.search(r"#Heatbath init\. time: (\S+) s", stdout)[1])
    acceptance = data_rows(output / "acceptance_rate.dat")
    assert [int(row[0]) for row in acceptance] == list(range(1, updates + 1))
    assert all(0 <= float(value) <= 1 for row in acceptance for value in row[1:3])
    energies = [float(row[1]) for row in data_rows(output / "dati.dat")]
    assert len(energies) == updates + 1 and all(map(math.isfinite, energies))
    assert all(old >= new for old, new in zip(energies, energies[1:]))
    assert len(data_rows(output / "topo.dat")) == (updates + 1) * 11
    if mode == "resume":
        assert math.isclose(energies[0], max(float(row[0]) for row in initial_energies),
                            rel_tol=0, abs_tol=1e-12)

    print(f"{name}: {wall / updates:.6f} s/update, {elapsed:.3f} s process wall", flush=True)
    return dict(mode=mode, stream=number, variant=variant, input_seed=seed,
                updates=updates, loop_wall_s=wall, loop_wall_s_per_update=wall / updates,
                loop_cpu_s=cpu_time, initialization_cpu_s=init_cpu, process_wall_s=elapsed,
                initial_cutoff=energies[0], final_cutoff=energies[-1],
                mean_z_acceptance=mean(float(row[1]) for row in acceptance),
                mean_u_acceptance=mean(float(row[2]) for row in acceptance))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New directory for logs, measurements and timings")
    parser.add_argument("--cpu", type=int, default=8)
    parser.add_argument("--resume-updates", type=int, default=20)
    parser.add_argument("--fresh-updates", type=int, default=12)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or min(args.resume_updates, args.fresh_updates) <= 0:
        parser.error("Choose an available CPU and positive update counts")

    result_dir = args.output.resolve()
    result_dir.mkdir()
    with tempfile.TemporaryDirectory(prefix="cpn_n21_l72_", dir="/tmp") as temporary:
        root = Path(temporary)
        print(f"Building revisions on {root}", flush=True)
        builds = {variant: build(root, variant, result_dir) for variant in REVISIONS}
        assert builds["baseline"][1] == builds["updated"][1]
        with (result_dir / "environment.txt").open("w") as environment:
            for command in (["uname", "-sr"], ["gcc", "--version"], ["lscpu"],
                            ["findmnt", "-T", temporary, "-n", "-o", "FSTYPE"]):
                subprocess.run(command, stdout=environment, check=True)
            print(f"Pinned logical CPU: {args.cpu}", file=environment)
            print(f"Configuration MD5 enabled: {builds['baseline'][1]}", file=environment)
            for variant, revision in REVISIONS.items():
                print(f"{variant}: {revision}", file=environment)

        checker = root / "baseline/checkpoint_energies"
        selected = select_checkpoints(checker, result_dir)
        checkpoints = {number: prepare_checkpoint(root, result_dir, builds["updated"][0],
                                                  checker, args.cpu, number, replace_dead)
                       for replace_dead, number in selected}
        print(f"Selected checkpoints: {list(checkpoints)}", flush=True)
        with (result_dir / "timings.csv").open("w", newline="") as csv_file:
            writer = None
            for mode, updates in (("resume", args.resume_updates), ("fresh", args.fresh_updates)):
                for index, (number, checkpoint) in enumerate(checkpoints.items()):
                    source = checkpoint if mode == "resume" else REPO / "out_data_ubelix" / f"run_{number}"
                    variants = tuple(REVISIONS)
                    if (index + (mode == "fresh")) % 2:
                        variants = variants[::-1]
                    for variant in variants:
                        row = run_trial(root, result_dir, builds[variant][0], args.cpu,
                                        mode, number, variant, updates, source)
                        if writer is None:
                            writer = csv.DictWriter(csv_file, fieldnames=row.keys())
                            writer.writeheader()
                        writer.writerow(row)
                        csv_file.flush()


if __name__ == "__main__":
    sys.exit(main())
