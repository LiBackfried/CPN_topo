# L90/L120 UBELIX timing and the L90 direct MCMC reference

Prepared for N=4, theta=0. NS uses source beta=0.7 at both volumes;
direct MCMC uses beta=0.95 at L90 and beta=1.0 at L120. This setup
submits short timing pilots and provides the L90 million-step MCMC
launcher. The L120 screening campaign and its beta=1.0 MCMC reference are
now prepared in [N4_L120_res/README.md](../N4_L120_res/README.md), including
dependent analysis and launch commands. No remote submission or timing
is implied by the prepared launchers.

## Build the two N=4 executables

Run on UBELIX from the CPN_topo root, before submitting:

```bash
# Bootstrap Autotools files if this checkout has not been configured yet.
module load foss/2025a OpenSSL/1.1
bash script_build_code.sh
bash N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
```

The existing NS helper restores the previous `include/macro.h` and
`cpn_ns`; the MCMC helper builds privately. The launchers require both
executables to report `Compiled with N = 4`.

## Start with the L90 benchmark

```bash
bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh
```

The default is L90 only. To time L120 or both volumes:

```bash
bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh 120
bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh all
```

Each volume submits six four-CPU jobs, with one single-threaded chain per
task, 512 MB per CPU and 45 minutes per job:

| Method | Beta | Proposals/update | Short | Long |
| --- | --- | --- | --- | --- |
| NS baseline | 0.7 | 3L²: 24,300 / 43,200 | 200 updates | 2,000 updates |
| NS candidate | 0.7 | 6L²: 48,600 / 86,400 | 200 updates | 2,000 updates |
| Direct MCMC | 0.95 / 1.0 | full MC steps | 2,000 steps | 20,000 steps |

NS retains 50 live points, initialization burn-in 20, live-point spacing
eight, four microcanonical sweeps, normalization every step and 50 cooling
steps measured every five. `num_ns_meas=updates+1`. MCMC measures every ten
steps, saves checkpoints every 1,000 steps and uses the same microcanonical,
normalization and cooling settings as the production reference.

Seeds are deterministic and matched between lengths and proposal counts;
tasks have distinct positive seeds. These short/long pairs and proposal
comparisons are timing experiments, not additional independent physics streams.
Repeated campaigns deliberately repeat the benchmark seeds.

The driver snapshots both executables, templates, worker and reporting script
in a new scratch `cpn_N4_L90_L120_timing.XXXXXX/` directory. SHA256 hashes,
Slurm logs, `jobs.tsv`, and a saved report command live there. Set `NS_SCRATCH`
to change the parent (default `/scratch/network/users/lb25v444/out_data`).
Absolute `NS_EXECUTABLE` and `MCMC_EXECUTABLE` overrides are supported.
Inherited `SBATCH_*` overrides are cleared for benchmark submission, and
NS parameter environment overrides do not alter the benchmark settings.

Inspect the reported allocations after submission:

```bash
sacct -j <JOB_IDS> --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
scontrol show job <JOB_ID>
```

Each timing allocation should have four CPUs. A worker writes `completed`
only after all four tasks succeed and measurement, topology, acceptance and
checkpoint checks pass. Every task has a separate working directory.
Output reuse is rejected. If submission fails partway through, inspect
`jobs.tsv` before starting another campaign; existing jobs are not cancelled.

## Report timings

Run the exact command printed by the driver, for example:

```bash
bash /scratch/network/users/lb25v444/out_data/cpn_N4_L90_L120_timing.XXXXXX/benchmark_L90_L120_ubelix.sh \
    report /scratch/network/users/lb25v444/out_data/cpn_N4_L90_L120_timing.XXXXXX/jobs.tsv
```

For each task the rate is `(long_wall-short_wall)/(long_steps-short_steps)`.
Only matching seed and CPU-model pairs are used. `paired_rates.tsv` stores
individual rates; `report.tsv` gives medians grouped by method, volume,
proposal count and CPU model, plus maximum measured RSS and full-length
projections. Incomplete jobs, mismatched pairs and invalid elapsed-time
differences produce diagnostics and a nonzero report status; available valid
pairs are still reported. A split CPU group can contain fewer than four pairs.

Full-length projections use 210k NS updates at L90, 370k at L120, twelve NS
streams, or one million MC steps with three MCMC chains. They exclude
initialization and assume the pilot rate persists. Per-chain wall time and
aggregate CPU-hours are different columns. Per-task `output_bytes.txt`
records the output-directory size after the pilot; it includes checkpoints.

[PERFORMANCE.md](PERFORMANCE.md) measured UBELIX baseline NS rates of
0.077683 and 0.143100 s/update at L90 and L120. Applying L66's local
15.7% proposal-doubling overhead projects approximately 0.090 and 0.166
s/update, or 5.2 and 17.0 hours for the depth budgets. These are estimates,
not new cluster measurements. Benchmark near the target cutoff again before
finalizing deep-run requests; early timing does not establish mixing or depth.

## Launch the L90 MCMC reference

After checking the L90 MCMC pilot rate, submit from the repository root:

```bash
sbatch N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh
```

The default requests three CPUs and twelve hours. See the
[reference README](mcmc_90_N4_beta0p95_3x100k/README.md) for output paths,
analysis and the provisional burn-in choice. These batch files must be
submitted with `sbatch`, including inside an Open OnDemand allocation.

## Local verification

```bash
bash N4_volume_benchmark/validate_L90_L120_launchers.sh
```

This uses mock Slurm commands and mock executables, verifies all benchmark
configurations and production counts, checks report arithmetic and failure
paths, and submits no remote jobs. It does not measure simulation performance.
