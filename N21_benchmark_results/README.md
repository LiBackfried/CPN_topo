# N=21 nested-sampling benchmark results

Collected on 24 November 2026. This directory brings together the local N=21
timing benchmarks and the reported UBELIX L=72 trials. Launch/build instructions
remain in [N21_L72_ubelix_benchmark](../N21_L72_ubelix_benchmark/README.md).

An external physics reference is now recorded in the
[Bonanno master's-thesis comparison](LITERATURE_COMPARISON.md): Table 4.2 of
the 2017 thesis, with beta=0.60/0.61 values and a normalized beta=0.60 comparison
to the 5,000-update NS trial. The largest listed marginal discrepancy is 1.65
combined SE; the broad NS errors limit what this agreement establishes.

The [Berni, Bonanno and D'Elia reference points](LITERATURE_COMPARISON.md#berni-bonanno-and-delia-2019)
record ξ_L and susceptibility for N=21 at β=0.68 on L=102 and β=0.70 on L=114.

**Main result:** on UBELIX, 15,500 proposals take **0.1812 wall seconds per NS
update** at L=72. Doubling to 31,000 takes **0.2305 seconds**, a **27.2%**
increase in the 5,000-update trial. The two proposal counts show no strong
marginal observable discrepancy, but these trials do not establish unbiased
initialization or constrained sampling. Retain 15,500 as a baseline for further
controlled trials; a larger proposal count has not demonstrated a clear overall
precision benefit here.

## Evidence and files

- [ubelix_reported_results.json](ubelix_reported_results.json): both UBELIX
  campaigns, four timing rows, fourteen observable-comparison rows, and all
  seventeen reported summary fields for each arm of the 5,000-update campaign.
  Includes simulation/analysis IDs, scratch paths, configured settings and
  derived planning estimates. Comparison-table and summary.txt precision are
  retained separately.
- [local_20261124_summary.json](local_20261124_summary.json) and
  [local_20261124_provenance.json](local_20261124_provenance.json): exact copies
  of the existing local benchmark aggregates and provenance. Per-trial local
  logs and data remain in their original directories, linked below.

**Provenance boundary:** UBELIX numbers were transcribed from the user's
terminal output in this chat. Remote scratch files, Slurm accounting, bootstrap
replicas and raw field configurations were not independently inspected or
downloaded. A reported `nan` uncertainty is represented as JSON `null` with
`reported_error: "nan"`; it is not replaced with zero.

## UBELIX campaigns

Both campaigns use N=21, L=72, source beta 0.6, theta 0, ten fresh streams per
arm, and 50 live points per stream. Settings retain four microcanonical sweeps,
20 initial heatbath sweeps, eight sweeps between live points, and cooling to
50 sweeps with measurements every five sweeps. Each arm is analyzed separately
with 500 whole-stream bootstrap replicates, seed 20261124, and `--cpn-n 21`.

| Updates per stream | 15,500-proposal simulation | 31,000-proposal simulation | Original analysis | Replacement analysis |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 23351015 | 23351016 | 23351017 | 23353763 |
| 5,000 | 23350970 | 23350971 | 23350972 | 23353908 |

Campaign and analysis locations:

```text
/scratch/network/users/lb25v444/out_data/
  ns_N21_L72_benchmark.uZevELp8/analysis_23353763/
  ns_N21_L72_benchmark.5NegZsTv/analysis_23353908/
```

The short campaign uses seeds 21721001–21721010 and 21721101–21721110.
The longer campaign uses 21720001–21720010 and 21720101–21720110. They are
separate ensembles; the short trial is not a prefix of the longer trial.

The original 100-update analysis failed because `srun` consumed the remaining
manifest input, skipping the second arm. This was reproduced locally and fixed
by isolating the manifest descriptor and disabling step standard input. The
replacement analyses use existing simulation outputs; no simulation rerun was
required. The original 5,000-update analysis's final state was not supplied.

## Measured UBELIX runtimes

All reported streams used an **AMD EPYC 7742 64-Core Processor**. Each timing
row summarizes ten concurrently launched streams. Loop wall time includes
updates, measurements, cooling and scratch I/O, while excluding initialization
and the first measurement. Ranges describe observed stream variation, not
confidence intervals.

| NS updates per stream | Proposals/update | Median wall s/update | Observed range, s/update | Maximum RSS, MiB |
| ---: | ---: | ---: | --- | ---: |
| 100 | 15,500 | 0.181514 | 0.178600–0.189242 | 8.0 |
| 100 | 31,000 | 0.211989 | 0.198312–0.232991 | 8.0 |
| 5,000 | 15,500 | 0.181234 | 0.179506–0.183682 | 8.0 |
| 5,000 | 31,000 | 0.230456 | 0.209790–0.234222 | 8.0 |

The 15,500-proposal medians differ by only 0.15% between the two campaigns.
The proposal-doubling cost is 16.8% in the short trial and 27.2% in the longer
trial. The 31,000-proposal median is 8.7% higher in the longer campaign; the
reported aggregate values do not separate depth effects from node/load
variation.

For planning, using the 5,000-update campaign's median loop rates:

| Proposals/update | 5,000-update loop duration from measured rate | Projected 10,000-update loop | Projected 50,000-update loop |
| ---: | ---: | ---: | ---: |
| 15,500 | 15.10 min | 30.21 min | 2.52 h |
| 31,000 | 19.20 min | 38.41 min | 3.20 h |

These are per-stream loop durations. The first column of durations is rate
times step count, not a separately supplied total-process median. Projections
assume that the measured rate persists and exclude initialization. Ten streams
ran concurrently; the duration is not multiplied by ten to obtain job elapsed
time. No 50,000-update N=21 UBELIX run is established by these results.

## Weighted observables: 5,000-update trial

Errors below are whole-stream bootstrap standard errors. The final column is
the reported difference `(31,000 - 15,500)` divided by the quadrature sum of
the two errors. It is a descriptive marginal comparison; the observables are
correlated and this is not an omnibus or equivalence test.

| Observable | 15,500 proposals | 31,000 proposals | Difference / combined SE |
| --- | ---: | ---: | ---: |
| Action density epsilon | 0.8582063 +/- 0.0000936 | 0.8584320 +/- 0.0001046 | +1.608 |
| G0 | 16.096 +/- 0.450 | 15.345 +/- 0.493 | -1.125 |
| Gk | 14.5685 +/- 0.2495 | 14.4865 +/- 0.1409 | -0.286 |
| xi_L squared | 13.777 +/- 4.067 | 7.787 +/- 4.699 | -0.964 |
| Mean Q_U | 0.3194 +/- 0.4219 | -0.0020 +/- 0.5279 | -0.476 |
| Mean Q_U squared | 4.038 +/- 1.086 | 4.350 +/- 0.791 | +0.232 |
| 10^4 chi_topological | 7.593 +/- 2.067 | 8.390 +/- 1.596 | +0.305 |

The largest difference is the action density, at 1.61 combined SE. Both mean
charges are compatible with zero at this precision. Errors are mixed: Gk and
susceptibility have smaller reported errors with 31,000 proposals, while action
density, G0 and xi_L squared have larger errors. Ten streams per arm do not
establish a reproducible overall precision gain from doubling proposals.

The reported correlation lengths are:

- 15,500 proposals: `xi_L = 3.71170041879 +/- 0.5783443`.
- 31,000 proposals: `xi_L = 2.79058467225 +/- nan`.

The second uncertainty is undefined, not zero. The implementation maps negative
bootstrap xi_L squared to `nan` before computing the ordinary standard deviation
of xi_L. This provides a mechanism for the reported undefined error; replicas
were not available to count invalid draws. Use the finite xi_L-squared estimate
`7.787 +/- 4.699` when discussing this unresolved square-root observable.

## Depth and interpretation

Both 5,000-update arms report `log_remaining_prior_mass = -100`, or
`remaining_prior_mass = 3.72007597602e-44`. This follows deterministic expected
shrinkage with 50 live points. It indicates negligible remaining quadrature
mass under that convention, not a measurement of mixing or initialization bias.
The reported `log_accumulated_prior_mass = 0` and compatibility alias `log_Z = 0`
describe source-prior coverage; they are not the physical canonical partition
function. Their zero bootstrap errors do not establish zero physics uncertainty.

At 100 updates, expected shrinkage instead gives approximately `exp(-2)=0.1353`
remaining mass. This is a derived estimate, not a pasted short-campaign summary
field. The largest proposal-count difference in that short campaign is only
0.602 combined SE, but the missing prior tail and distinct seeds prevent using
short-versus-long agreement as a paired convergence demonstration.

At the source beta, most weight lies in the earlier NS ranks. Once source-prior
coverage is adequate, simply extending an existing stream much deeper adds
little source-beta weight. Additional independent streams, initialization
studies and fixed-cutoff mixing tests address different questions. Deeper
trajectories can be needed for larger target beta; no useful N=21 reweighting
range has been established by these source-beta reports.

## Local benchmarks and old runtimes

The [24 November local report](../N21_volume_benchmark_20261124/REPORT.md) uses
three sequential seeds and 100 NS updates per case on an AMD Ryzen 7 8845HS,
Ubuntu-24.04 WSL2, GCC 13.3.0, pinned to logical CPU 8, with WSL ext4 I/O and
configuration MD5 disabled.

| L | Start | Proposals/update | Median loop wall s/update | Initialization CPU s |
| ---: | --- | ---: | ---: | ---: |
| 72 | Continuation | 5,000 | 0.082742 | 0.0043 |
| 72 | Fresh | 5,000 | 0.077128 | 6.26 |
| 72 | Fresh | 15,500 | 0.088116 | 6.33 |
| 150 | Fresh | 67,500 | 0.476500 | 28.37 |

The current UBELIX 15,500-proposal wall rate is about 2.06 times the local fresh
rate. Hardware, concurrency, filesystem and MD5/build settings differ, so that
ratio does not isolate a CPU effect or a code regression. There is no measured
L=150 UBELIX result in the supplied evidence, and no old L=150 runtime.

Historical pre-optimization comparisons, with each row using a consistent
timing metric:

| L=72 workload | Historical old rate | 24 November optimized local rate | Speedup |
| --- | ---: | ---: | --- |
| 5,000 proposals, continuation | 2.9640 wall s/update | 0.082742 wall s/update | 35.0x, median seed-matched ratios |
| 5,000 proposals, fresh | 2.9414 wall s/update | 0.077128 wall s/update | 37.6x, median seed-matched ratios |
| 15,500 proposals, fresh | 10.7789 CPU s/update | 0.084205 CPU s/update | 128.0x, historical mean/current median |

The 5,000-proposal historical data come from the
[16 November matched benchmark](../N21_L72_benchmark_20261116/REPORT.md);
the old 15,500-proposal CPU times come from the
[20 October smoke test](../N4_L22_runs/smoke_runtime_20261020/README.md).
The historical trajectories are shorter. There is no matched old/new N=21
UBELIX speedup measurement here, and local CPU times must not be divided by
UBELIX wall times to claim one.

The already-optimized 16 November code measured 0.07495 wall s/update for L=72
continuations and 0.07323 for fresh starts with 5,000 proposals. The 24 November
simulation/build source matched that optimized version; these are repeated
measurements, not a further optimization. Earlier local validation found
matching acceptance fractions, cutoff differences below 2.5e-12 against the old
baseline, and matching recomputed energies in the private benchmark checkpoints.
Original legacy checkpoints contained an inconsistent maximum-energy slot;
fresh UBELIX trials did not resume those snapshots.

## Next physics checks

At L=72 the active study is **β=0.60 → 0.61**. The β=0.68–0.76 L=72 scan
is on hold.
[Near-source study](L72_NEAR_SOURCE.md) · [Results of job 23365849](L72_NEAR_SOURCE_RESULTS.md) · [Deferred scan notes](L72_TARGET_BETA.md)

The L=72 direct MCMC comparisons favor 31,000 proposals per NS update at
the current 5,000-update depth. The β=0.60 MCMC prior check shows strong
topological correlations at the current eight-cycle live-point spacing.
Resolve warmup and spacing with longer source trajectories, then check
charge mixing in fixed-cutoff trials. The L=150 follow-up is set up
for 200,000 cycles per hot chain to check autocorrelations before NS.
[MCMC results and next runs](MCMC_VALIDATION_RESULTS.md) · [MCMC launch setup](MCMC_VALIDATION.md)
