# L66 campaign and analysis outputs

The shared seven-beta L22/L38/L66 reweighting workflow is now available:

```bash
INCLUDE_L66=1 bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

It uses existing NS jobs `22587433`, `22587434`, `22587435` and the direct
beta=0.9 MCMC reference `22587511` when available. Results, normalized-weight
overlays and three-volume comparisons are saved to a new repository
`N4_L66_res/volume_scan.XXXXXX/`. Passing a completed L22/L38 scan directory
as the optional argument reuses those analyses. See
[VOLUME_BETA_SCAN.md](../N4_volume_benchmark/VOLUME_BETA_SCAN.md) for commands,
resource overrides and the handling of unresolved low-beta xi.

Copied completed NS and MCMC comparison analyses are now available in
`campaign.HP4pX0/` and `comparison_22587511/`. See
[RESULTS_REVIEW.md](RESULTS_REVIEW.md) for the matched beta=0.9 comparison,
depth checks through beta=1.0 and unresolved low-beta correlation lengths.

The local L22/L38/L66 comparison is in
[volume_comparison_local/README.md](volume_comparison_local/README.md), with
[findings](volume_comparison_local/FINDINGS.md) and
[six-panel plot](volume_comparison_local/volume_dependence.png). It uses
25 local L22 streams and leaves the four locally missing L38 betas as gaps.

Save all future L66 analysis here, including submission manifests, depth
scans, MCMC plots/binning and NS/MCMC comparisons. Simulation checkpoints
and raw measurements remain on UBELIX scratch. Nothing was submitted by
the assistant. `reference_targets.csv` transcribes the user's attached
N=4 Table III; its original paper was not identified from the image.

## Reported UBELIX job IDs

On 2026-11-18 the user reported MCMC job **22587511** (L66, beta=0.9)
and NS simulation job IDs **22587433, 22587434, 22587435**
(source beta=0.7), with dependent analysis job **22587436**.
Submission and job roles are user-confirmed; copied analysis directories
now contain completion markers. Remote Slurm state has not been checked.
The job IDs are also recorded in
`reported_jobs_20261118.tsv`.

The three NS simulation jobs contain four streams each, for **12 independent
streams** in total. The user confirmed that **22587436 is the dependent
analysis job**; it contributes no simulation streams. Check, for example:

```bash
sacct -j 22587433,22587434,22587435,22587436,22587511 \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

The expected MCMC data directory is
`/scratch/network/users/lb25v444/out_data/mcmc_66_N4_beta0p9_3x100k/job_22587511/`.
NS simulation jobs use
`/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L66/job_<ID>/`;
the dependent analysis uses the repository `N4_L66_res/campaign.XXXXXX/`
directory recorded by the driver.

## Targets and existing analysis

The matching L66, beta=0.9 table row has xi_L=5.398(22), xi_L²=29.1384(2375)
and L/xi_L=12.227. Scan targets remain beta=0.7 through 1.0. At L66 the
table's beta=1.0 value xi_L=9.997 belongs to L120, so it is a useful scale
estimate, not an exact finite-volume target for L66 (L/xi would be about 6.6).

Previously saved L22, beta=0.7 analysis (`analysis_results/ns_constraint_22_N4_beta0p7_800x50000_stoc1500/job_20793993/results.json`)
gives xi_L=1.7671 ± 0.0356, consistent with table 1.7842(59).
The L38, beta=0.8 row in `N4_L38_res/L38_depth_combined16.csv` at 35k
gives xi_L²=9.9573(1.0981), or xi_L approximately 3.1555(1740), consistent
with table 3.039(12). The error on the square root is propagated to first
order from the saved xi_L² bootstrap error. At beta=0.9 that L38 ensemble
gives xi_L²=30.1873(1.2667), near the L66 target 29.1384(2375), but these
are different volumes. The direct L66 run provides the matching-volume test.
Completed L66 estimates and their limitations are in `RESULTS_REVIEW.md`.

## Initial NS setup

- N=4, L=66, source beta=0.7, theta=0; 50 live points per stream.
- Twelve independent streams in three four-CPU jobs, 110,000 updates each;
  generated `num_ns_meas=110001` includes the initial measurement.
- 26,136 stochastic proposals/update = 6L². The baseline 3L²=13,068 is
  already three times L38's 4,332. Doubling matches the latest L38
  doubled-proposal ensemble (8,664), whose validation remains in progress.
- Match L38 initialization: 20 MC burn-in steps and eight MC steps between
  saved live points; four microcanonical sweeps, normalization every step,
  50 cooling steps measured every five. This initialization and constrained
  mixing still require physics checks at L66, including longer initialization
  and proposal-count comparisons if diagnostics disagree.

The depth estimate is 35,000*(66/38)²=105,582 updates, rounded to 110,000.
This extensive-energy scaling is a planning assumption. The saved L38
beta=1.0 q99 lies near 26,649 dead points per stream; volume scaling gives
about 80,390, motivating prefix checks at 20k, 40k, 60k, 80k and 100k,
plus the deepest common prefix. Neither estimate guarantees target coverage.

## Submit on UBELIX

From the repository root, build the NS executable before submitting. The
existing helper restores the previous `include/macro.h` and `cpn_ns`.

```bash
bash N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh
bash N4_volume_benchmark/fresh_L66_12_ubelix.sh
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
sbatch N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh
```

The NS submission driver submits three simulation jobs and an `afterok`
analysis job. It writes job IDs, paths, and an analysis retry command to a
new `N4_L66_res/campaign.XXXXXX/` directory. Simulations request four hours;
the 200-replicate whole-stream depth analysis requests eight hours and 16 GB.
NS raw data go to `$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L66/job_<ID>/`
(default scratch base `/scratch/network/users/lb25v444/out_data`). Job IDs
generate distinct NS seeds; MCMC uses 4106601, 4106602, 4106603.

After submission verify each allocation, for example:

```bash
sacct -j <JOB_ID> --format=JobID,State,AllocCPUS,Elapsed,ExitCode
scontrol show job <JOB_ID>
```

Require four CPUs per NS job and three for MCMC. The driver invokes
`sbatch`; do not run the batch job files themselves with `bash` or `./`.

## Compare and continue

After all three NS jobs and MCMC finish, include the optional MCMC ID:

```bash
sbatch N4_volume_benchmark/analyze_L66_ubelix.sh \
    <NS_JOB1> <NS_JOB2> <NS_JOB3> \
    "$PWD/N4_L66_res/comparison_<MCMC_JOB_ID>" <MCMC_JOB_ID>
```

This writes `depth.csv`, `mcmc_full/`, `mcmc_burn20000/`, and
`action_bins32_beta0p9/` under that repository directory. It passes
`--beta 0.9 --updates 110000` explicitly to the bin comparison. Inspect
burn-in and bin-size dependence before treating its default cut/block size
as final. All beta scans use normalized source-prior quadrature, beta-only
reweighting with N=4, and whole-stream bootstrap errors.

Check low-energy-edge weight (<1% is only an initial screen), successive
prefix stability relative to bootstrap errors, stream concentration,
acceptance and Q histories near the target band. Compare weighted action,
correlation length and topology to MCMC at beta=0.9. A small edge weight
cannot by itself rule out unseen target weight. Keep proposal counts or
initialization settings in separate ensembles.

If depth is inadequate, continue each completed four-stream job separately:

```bash
base="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/ns_N4_beta0p7_volume_benchmark/L66"
sbatch --ntasks=4 --time=01:00:00 N4_volume_benchmark/run_ubelix.sh 66 20000 "$base/job_<PARENT>"
```

Use clean environment variables: unset `NS_STOC`, `NS_INIT_SWEEPS`,
`NS_INIT_SPACING`, `NS_SEED_BASE` and `NS_EXECUTABLE` for continuations.
The existing launcher copies validated checkpoints into a new job directory,
inherits RNG/executable/settings and writes parent links. Scan only the
three new leaves; preserve their ancestors. For comparisons at another
depth, invoke `compare_action_bins.py` with that depth and an output under
`N4_L66_res/`.

## Runtime evidence

See `N4_volume_benchmark/PERFORMANCE.md` for the completed UBELIX timing
campaign. At L66, beta=0.7 and 13,068 proposals it measured 0.045886 s/update
on EPYC 7742: about 84.1 minutes for 110,000 updates per stream, excluding
initialization. Doubling just the proposals is not expected to double the
entire runtime because cooling/measurement/I/O costs remain. A conservative
full-rate doubling gives 168.2 minutes; four hours gives headroom. Twelve
streams running concurrently have this per-job wall-time scale, with
aggregate CPU consumption twelve times the per-stream time. Deep-cutoff
timings, scratch contention and node differences can change the rate.

`benchmark_L66_local.sh` builds both N=4 executables in a private WSL Linux
directory without changing the checkout's compile-time N. It runs matched
100/1100-update NS pilots at 13,068 and 26,136 proposals for two seeds, and
1000/11000-step MCMC pilots with production measurement/cooling/checkpoint
settings. Results are in `local_benchmark_20261118/`; short/long differences
remove most initialization overhead. These early-depth timings do not
validate mixing or reweighting through beta=1.0.

Completed local results (2026-11-18, Ryzen 7 8845HS, GCC -O3, WSL,
private Linux-filesystem runs, MD5 disabled as in the prior local benchmark):

| Run | Seed 806601 | Seed 806602 | Median rate | Full-length local projection |
| --- | ---: | ---: | ---: | ---: |
| NS, 13,068 proposals | 23.65 ms/update | 21.42 ms/update | 22.535 ms/update | 41.3 min / 110k |
| NS, 26,136 proposals | 27.35 ms/update | 24.79 ms/update | 26.070 ms/update | 47.8 min / 110k |
| MCMC, measured every 10 | 5.693 ms/step | 5.955 ms/step | 5.824 ms/step | 97.1 min / 1M |

Rates use `(long_seconds-short_seconds)/(long_steps-short_steps)`.
The proposal doubling increases measured NS time by about 15.7%. Applying
that ratio to the historical UBELIX baseline projects 53.1 ms/update,
or 97.3 minutes per 110k stream (19.5 CPU-hours across twelve streams).
This is a projection, not a new cluster measurement; the conservative
168-minute NS budget above remains useful. The local-to-historical-UBELIX
NS ratio is about 2.04; using it for MCMC gives a rough 3.3-hour projection
per million-step chain. That cross-kernel conversion is less reliable than
the NS estimate, so inspect actual MCMC timing and allow more wall time if
the pilot rate differs. Both simulation launchers request four hours.

Both local N=4 executables built successfully. The benchmark checked all
NS update counts and MCMC data-row counts; peak measured RSS was about
5.2 MiB. `launcher_validation.log` records passing shell syntax/LF checks,
mock three-job submission and analysis dependencies, NS config/seed checks,
MCMC output-count checks, wrong-N/duplicate-seed/output-reuse rejection,
analysis argument routing, and repository output containment. Mock IDs in
that log are local test values, not UBELIX job IDs. No Python or simulation
source code was changed for this setup.
