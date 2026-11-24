# N=21 nested-sampling runtime: L=72 and L=150

Measured locally on 24 November 2026.

The optimized setup takes **0.0881 s per NS update at L=72 with 15,500 proposals**
and **0.4765 s at L=150 with 67,500 proposals**. With the older 5,000-proposal
L=72 workload, it takes 0.0771 s from a fresh start and 0.0827 s in continuations.

## Current measured runtimes

Three independently seeded trials per row, each with exactly 100 NS updates
(`num_ns_meas=101`). Times are medians; ranges are the observed minimum and
maximum across the three trials, not confidence intervals.

| L | Start | Proposals per NS update | Loop wall s/update | Observed range | Loop CPU s/update | Initialization CPU s | Total process wall s, 100 updates |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 72 | Continuation | 5,000 | 0.08274 | 0.08210–0.08466 | 0.07934 | 0.0043 | 8.34 |
| 72 | Fresh | 5,000 | 0.07713 | 0.07706–0.08228 | 0.07505 | 6.26 | 14.40 |
| 72 | Fresh | 15,500 | 0.08812 | 0.08493–0.09183 | 0.08421 | 6.33 | 15.45 |
| 150 | Fresh | 67,500 | 0.47650 | 0.44325–0.51128 | 0.46085 | 28.37 | 77.47 |

Here “new setup” means the current optimized heatbath NS implementation, with
the existing N=21 production physics and measurement settings. Both established
L=72 proposal counts are retained. L=150 uses the suggested `3L²=67,500`
proposals; L=72's 15,500 is close to `3L²=15,552`. No existing L=150 production
input or old runtime was found locally. Its input is a benchmark setup at beta
0.6, rather than a validated production choice for that volume.

Increasing the L=72 proposal count from 5,000 to 15,500 increases median fresh
loop wall time by 14.2%. Comparing the approximately `3L²` workloads, L=150
takes 5.41 times the L=72 time per NS update; the lattice volume ratio is 4.34.

## Comparison with saved old timings

The pre-optimization local L=72 measurements are available in
`N21_L72_benchmark_20261116/results/timings.csv` and
`N4_L22_runs/smoke_runtime_20261020/benchmark_summary.csv`.

| L=72 workload | Old timing | Current timing, same metric | Historical/current speedup |
| --- | ---: | ---: | ---: |
| 5,000 proposals, continuation | 2.9640 wall s/update | 0.08274 wall s/update | **35.0×**, median of seed-matched ratios |
| 5,000 proposals, fresh | 2.9414 wall s/update | 0.07713 wall s/update | **37.6×**, median of seed-matched ratios |
| 15,500 proposals, fresh | 10.7789 CPU s/update | 0.08421 CPU s/update | **128.0×**, historical mean/current median |

The November 16 pre-optimization build was revision `5428e2b`. Its trials used
20 continuation updates and 12 fresh updates per seed, with seeds 16774–16776.
The new trials use those same seeds and initial states, with longer trajectories.
Speedups are the median of the three within-seed ratios; they need not equal
the ratio of the displayed medians. The CPU-time speedups for these two
5,000-proposal workloads are 37.8× and 38.7×, respectively.

The October 20 measurements used two five-update trials at seed 46774. That
campaign saved loop CPU time, so its comparison above uses current CPU time
too. It is a comparison across dates and trajectory lengths, not a newly run
paired benchmark. The larger speedup at 15,500 proposals reflects the cost of
the old implementation's per-proposal full-lattice work.

The already-optimized November 16 timings were 0.07495 wall s/update for
continuations and 0.07323 for fresh starts at 5,000 proposals. The current
measurements are 10.4% and 5.3% higher. The simulation/build source files are
unchanged between that optimized revision (`37d1e55`) and this campaign's
revision (`fed72be767650822668161e11e1285b0e4dbe581`). These measurements use
longer trajectories on a different day; they do not establish a code regression.

No measured old L=150 runtime is available, so no L=150 optimization speedup
is assigned.

## Planning estimates

Multiplying the measured median wall time by 10,000 gives approximately
**13.8 minutes** for L=72 continuations with 5,000 proposals, **14.7 minutes**
for L=72 with 15,500 proposals, and **79.4 minutes** for L=150 with 67,500
proposals, per stream. Fresh initialization adds roughly 6 seconds at L=72
and 28 seconds at L=150 on this machine.

These are extrapolations from 100-update trials. L=150 was measured only near
a fresh canonical initialization; later constrained depths and longer runs may
have different costs. These are single-stream local results. UBELIX wall time,
scratch-filesystem performance, and simultaneous-stream throughput were not
measured.

## Method and checks

- AMD Ryzen 7 8845HS, Ubuntu-24.04 WSL2, GCC 13.3.0, repository `-O3` flags.
  All timed simulations ran sequentially, pinned to logical CPU 8.
- Each isolated build explicitly sets compile-time N=21 and verifies the
  executable banner. The repository header and executables are untouched.
- Beta 0.6, theta 0, 50 live points, four microcanonical sweeps, `num_norm=1`,
  50 cooling sweeps with measurements every five sweeps, no saved dead
  configurations. Fresh initialization uses 20 heatbath sweeps followed by
  eight sweeps between live points.
- Build and simulation scratch directories use WSL's ext4 filesystem.
  Configuration MD5 checking is disabled in the private build because OpenSSL
  development headers are unavailable, matching the November 16 build.
- Identical `CLOCK_MONOTONIC` probes delimit the NS loop. Loop time includes
  configuration I/O, updates, cooling, and measurements, and excludes live-point
  initialization and the initial measurement. Process wall time includes them.
  Copying results back to the repository is excluded from process timing.
- The checkpoint audit verified all 500 saved configuration hashes and
  recomputed energies across ten local L=72 snapshots. Each snapshot retains
  the previously documented inconsistent maximum-energy slot. One untimed
  update repaired that slot on private copies of runs 0–2; all 50 energies then
  agreed exactly with recomputation. Original snapshots remained read-only.
- Every timed trial passed measurement, cooling-row, acceptance-row, finite
  energy, and monotonically decreasing cutoff checks. All 12 final private
  checkpoints had zero stored-versus-recomputed energy difference.
- On the overlapping historical 5,000-proposal trajectories, acceptance
  fractions matched at every step. Maximum cutoff differences versus the old
  baseline were 2.45e-12 for continuations and 1.72e-12 for fresh starts. The
  saved October five-step acceptance sequence also matched. These checks
  support numerical consistency, not constrained-chain mixing or thermalization.
- Python compilation passed for the analysis modules and both new benchmark
  scripts. All 38 repository unit tests passed in `fpaction2`. A two-stream,
  200-dead-point analysis with a 10-replicate stream bootstrap succeeded; its
  temporary outputs were removed. Logs are saved as `validation_tests.log`
  and `validation_analysis.log`. `git diff --check` passed; unrelated existing
  N=4 changes were preserved.

## Reproduce and inspect

From the repository root inside Ubuntu-24.04 WSL:

```bash
python3 N21_volume_benchmark_20261124/benchmark.py \
  N21_volume_benchmark_20261124/repeat_results --cpu 8 --updates 100
python3 N21_volume_benchmark_20261124/summarize.py \
  N21_volume_benchmark_20261124/repeat_results
```

Use a new output directory. The benchmark builds committed sources and checks
for uncommitted simulation-source edits, ignoring line-ending-only differences.
It requires the local `out_data_ubelix` checkpoints. Private builds and large
checkpoint copies are removed automatically after completion.

`results/timings.csv` contains all 12 trial timings and acceptance/cutoff
summaries. `results/summary.json` contains aggregates and historical comparisons.
`results/provenance.json`, `environment.txt`, build logs, executable banner,
checkpoint audit, repair verification, and per-trial inputs and raw measurement
outputs retain the evidence needed to inspect the campaign.
