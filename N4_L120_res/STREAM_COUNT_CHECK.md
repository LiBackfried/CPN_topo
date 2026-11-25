# L120: impact of increasing the number of streams

Prepared on 2026-11-25. This is post-processing of the **existing 24 streams**
at 300k updates, source beta=0.7, N=4, L120, target beta=1.0. It submits no
simulation runs and needs no executable rebuild. No analysis jobs have yet
been submitted from this local setup.

## Run on UBELIX

Sync `scan_stream_count.py`, `run_L120_stream_count_ubelix.sh` and
`submit_L120_stream_count_ubelix.sh` under `N4_volume_benchmark/`, together
with their imported existing Python analysis modules. Then run:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh
```

The helper prints all job IDs, a campaign directory
`N4_L120_res/stream_count24.<random>/`, and the final report path. Default
raw inputs are the six completed leaves below and MCMC **22780263**:

| Cohort | NS leaf IDs | Independent streams |
| --- | --- | ---: |
| Original twelve | 22885157, 22904262, 22904264 | 12 |
| Added twelve | 23350703, 23350705, 23350707 | 12 |

Override the scratch root with `NS_SCRATCH=/absolute/path` when submitting.
Raw data and all continuation parents remain read-only.

## Analysis design

Preparation validates the raw histories using the existing scanner, including
parent links, repeated boundary rows, N=4 logs, distinct seeds, compatible
settings, and exactly 300k cumulative updates for each of the 24 streams.
It checks L120/86,400 proposals, 50 live points per stream, source beta=0.7,
theta=0 and the three-chain beta=1.0 MCMC reference. It caches the six needed
measurement columns as compact NumPy files, with source/data SHA256 hashes.
Raw topology text is parsed once rather than once per array task.

**Task 0 compares old12, new12 and full24.** Each ensemble is re-merged and
reweighted independently with its actual live count (600/600/1,200). Each
gets whole-stream bootstrap errors and the existing conditional-comparison
outputs, including covariance, simultaneous intervals and approximate joint
max-residual diagnostics over G0/Gk and all 32 bins. Old-minus-new differences
combine their two NS errors only: the shared MCMC reference cancels.

**Tasks 1-8 implement eight reproducible random stream orderings.** For each
ordering take its first **6, 8, 12, 16 and 20 streams**, without replacement
within each subset. These subsets are nested within an ordering. Re-merge
and recompute NS shrinkage/weights for each subset and every bootstrap draw.
The **full24** result is calculated once in task0 and reused, not recomputed
eight times. All subsets stay at the same cumulative 300k production depth.

Freeze the common low-energy cutoff from all 24 streams and the MCMC-derived
32-bin edges across every subset and both disjoint cohorts. Use the central
99% MCMC action range, a 20,000-MC-step cut and blocks of **512 measurements**
(5,120 MC cycles). This matches the current 24-stream production comparison's
bin/block definition. Track action density, xi_L_squared, susceptibility,
G0, Gk, log_Z_ratio, and conditional G0/Gk in every action bin. Bin9 is the
preselected highlighted G0 range, not a bin selected anew in each subset.

Defaults are **200 whole-stream bootstrap draws per subset**, **1,000 joint
draws for each old/new/full comparison**, and seed **20261125**. No raw
bootstrap replicas are saved. The eight orderings yield 40 proper subsets
plus the three controls: 43 ensembles in total. Approximate work is 8,600
NS bootstrap replicates plus central estimates, at one target beta.

## Jobs, resource limits and recovery

| Stage | Slurm jobs/tasks | CPUs/task | Memory/task | Time limit/task |
| --- | --- | ---: | --- | --- |
| Validate and cache | One preparation job | 1 | 32 GB | 12 h |
| Evaluate controls/subsets | Array 0-8, **at most two tasks at once** | 1 | 32 GB | 24 h |
| Collect tables/plots | One job after all array tasks succeed | 1 | 4 GB | 1 h |

These are allocation limits, not measured runtime predictions. Actual
compute usage depends on the stream merges and bootstrap evaluations. All
BLAS/OpenMP thread counts are restricted to one. Preparation must complete
before the array; collection waits with `afterok` for the entire array.

The helper accepts `STREAM_COUNT_ORDERINGS` (1-64),
`STREAM_COUNT_BOOTSTRAP`, `STREAM_COUNT_JOINT_DRAWS` and `STREAM_COUNT_SEED`
before a fresh submission. The count grid remains 6/8/12/16/20/24. For
example, four orderings halve the subset evaluations while giving a coarser
view of subset variation. Stored settings and all selected stream IDs/seeds
are recorded in the campaign/cache provenance.

Each completed subset is atomically saved before the next one starts. If
an evaluation fails or times out after successful cache preparation, run:

```bash
bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh \
    --resume /absolute/path/to/N4_L120_res/stream_count24.<random>
```

This submits another evaluation array and collector against the same cache,
reuses completed subsets, and finishes missing ones. It does not reread raw
simulation text. Source/data hashes and task signatures prevent mixing
different inputs or settings. An incomplete cache requires a fresh campaign;
partial work directories are retained for inspection. `jobs.tsv` records
submissions, `raw_inputs.tsv` records the six leaves and MCMC, and
`resume_command.txt` contains the concrete recovery command.

## Reading the results

Final output is `stream_count24.<random>/report_<COLLECT_JOB>/`:

- `baseline_observables.csv`: old12, new12 and full24 central values, NS
  errors and MCMC comparisons.
- `old_new_differences.csv`: independent old-minus-new NS comparisons,
  for integrated quantities and conditional correlators. Marginal
  standardized entries are descriptive, not adjusted for searching bins.
- `subset_observables.csv` / `subset_bins.csv`: every selected subset,
  its NS bootstrap errors and residuals against the shared MCMC reference.
- `scaling_summary.csv`: central-value median/range, subset scatter,
  median/range of NS errors, SE*sqrt(k), and full24 SE*sqrt(24/k).
- `conditional_scaling.csv`: the analogous summaries for each fixed bin.
- `error_scaling.png`, `estimate_scaling.png`, `focus_G0_scaling.png`:
  precision curves, central-value stability, and the highlighted G0-bin trend.

The old/new/full covariance/joint plots and tables are under
`evaluations/task_0/{old12,new12,full24}/comparison/`. A completion marker
on the final report confirms that all planned tasks were collected.

Keep **finite-population subset scatter separate from bootstrap precision**.
At k=24 there is only one full dataset, so subset scatter is zero while its
bootstrap error remains nonzero. Shaded 10-90% subset ranges are descriptive
ranges, not confidence intervals. Overlapping subsets and nested counts
are correlated: do not combine their errors as if independent, or treat
eight orderings as eight independent simulation ensembles. Conditional on
the fixed common support/edges, the old and new twelve-stream cohorts use
disjoint seeds and permit an independent NS-error comparison.

An approximate 1/sqrt(k) error trend supports the expected precision gain.
A stable nonzero conditional residual with shrinking errors motivates
sampling validation; it does not identify its cause. The joint diagnostics
are approximate, use fixed estimated bin edges and have a finite NS
bootstrap pool. Increasing the number of streams does not establish prior
thermalization or rule out a shared constrained-sampling bias.
