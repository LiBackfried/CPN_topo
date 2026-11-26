# L120 doubled-proposal ensemble: eight to 24 streams

Prepared locally on 2026-11-26 at the user's request. No jobs have been
submitted from this checkout. The campaign adds **sixteen fresh independent
NS streams**, keeping the existing eight at 172800 proposals/update.
It does not extend their depth or add streams to the 86400-proposal baseline.

## Submit on UBELIX

Sync the updated checkout, then run from its root on a login node:

```bash
bash N4_volume_benchmark/add_L120_proposals_8to24_ubelix.sh
```

The helper submits **thirteen jobs**: four independent four-stream batches,
each with three dependent simulation stages, followed by one analysis job
after all four new leaves succeed. It automatically reuses old leaves
**23502237 and 23502240**, baseline24 leaves **22885157, 22904262,
22904264, 23350703, 23350705, 23350707**, and MCMC **22780263**.
The four fresh batches may run concurrently (sixteen single-CPU streams);
Slurm determines when resources are available.

Each fresh stream keeps:

| Parameter | Value |
| --- | --- |
| N, L | 4, 120 |
| Source beta, theta | 0.7, 0 |
| Proposals per NS update | 172800 = 12 L² |
| Live points per stream | 50 |
| Initialization cycles / live-point spacing | 20 / 8 |
| Cumulative NS updates | 300000 |
| Stages | 100000 + 100000 + 100000 |
| NS measurements per segment | 100001, including its initial measurement |

The expanded cohort has 24 independent streams and 1200 effective live
points when merged. The 86400-proposal baseline remains a separate
24-stream ensemble. Initialization is held fixed to isolate stream-count
effects; the earlier warmup caveat is not silently changed by this setup.

Simulation stages request **four CPUs, 512 MiB/CPU, twelve hours** each,
using the same stage budgets as the completed doubled-proposal pilot.
The dependent analysis requests **one CPU, 8 GiB, eight hours**. Actual
timings of the previous 172800-proposal streams were not pulled locally,
so these are allocation budgets, not new runtime measurements.

## Inputs, seeds and continuation safety

No rebuild is needed. The saved N=4 executable from NS job 23502237 is
verified and copied into every fresh job. The helper checks all 32 existing
NS stream records, follows their parent links, verifies matching settings
and cumulative 300k depth, and checks required historical data/log files
without loading large histories on the login node. The MCMC reference is
also checked before submission.

Sixteen positive seeds are allocated in four groups of four. They are
checked against all 32 existing NS seeds, three reference MCMC seeds, four
source-pilot seeds, each other, and any earlier expansion's planned seeds.
Every stream has a separate working directory.

Fresh segments use start=1/rng_start=0. Continuations use start=2/rng_start=1,
copy validated live configurations and RNG checkpoints into new job-specific
directories, and inherit settings and the executable. Their five NS override
variables are explicitly unset. Parents and old streams remain unchanged;
keep every ancestor directory. The analysis follows parent links and removes
the repeated checkpoint measurement at each join.

Scratch output uses the existing family:

```text
/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L120/job_<JOB_ID>/
```

`NS_SCRATCH` can override the scratch base. Campaign records and logs are
created under:

```text
N4_L120_res/proposals172800_add16.<random>/
```

The directory contains `jobs.tsv`, `existing_streams.tsv`,
`excluded_seeds.tsv`, `planned_seeds.tsv`, settings, source/executable
hashes, revision, Slurm logs and `retry_analysis.txt`. Submission records
are written after each successful job submission. If submission partially
fails, inspect these records before taking further action; do not rerun the
fresh-campaign helper to retry an analysis or already queued stages.

## Dependent analysis

Results are written to:

```text
N4_L120_res/proposals172800_24streams_analysis_<ANALYSIS_JOB_ID>/
```

The parent `completed` marker is written only after both analysis phases and
provenance saving succeed. Pull this entire directory back.

`proposal_comparison/` contains:

- Matched baseline24/control24 canonical observables at beta=1 and direct
  differences with NS-only errors (the shared MC reference cancels).
- Separate **old8** and **fresh16** checks, including their independent
  differences. These cohorts are disjoint; both overlap the full control24.
- Conditional G0/Gk comparisons in the same 32 MC-quantile action bins,
  covariance, simultaneous intervals and approximate joint diagnostics.
- **Action distributions with marginal uncertainty bands**, and separate
  action-bin joint diagnostics/covariance. Action and correlator diagnostics
  are distinct families, not one globally calibrated test.
- Control24 depth checks at 240k/270k/300k updates, using paired stream
  bootstrap draws across depths.
- Stream-count checks at **8/12/16/24**, using four random nested orderings
  for the smaller sizes and one full24 result. CSVs, selections, estimate
  plots and error-scaling plots compare errors with full SE x sqrt(24/k).
  These overlapping subsets describe ordering dependence; they are not
  independent new ensembles or independent tests of the full24 estimate.

`charge_distributions/` contains weighted Q_U/Q_z/Q_plaquette histogram
exports and baseline24/control24/MCMC overlay plots in linear/log views.
NS bootstrap errors resample whole streams and recompute weights.
The MC reference keeps burn-in 20000 steps and block size 512 measurements.
Both analyses use 200 NS bootstrap draws; joint diagnostics use 1000 draws.

The full and old/fresh comparisons assess whether the action shift and G0
features persist as independent coverage increases. The expected 1/sqrt(K)
scaling would reduce errors by about 42% from eight to 24 streams; this is
a reference scaling, not an imposed outcome or a guarantee of mixing.

## Retry only the analysis

After all four new leaves complete, use the saved `retry_analysis.txt`.
The equivalent command from the repository root is:

```bash
sbatch N4_volume_benchmark/analyze_L120_proposals24_ubelix.sh \
  NEW_LEAF1 NEW_LEAF2 NEW_LEAF3 NEW_LEAF4
```

Each retry uses its new Slurm job ID for a separate result directory.
The existing eight and all baseline/reference paths are supplied by the wrapper.

## Local validation

```bash
bash tests/test_L120_proposal_expansion_launchers.sh
python -m unittest discover -s tests -v
```

The shell test uses mocked executables and Slurm commands; it exercises all
twelve simulation stages, thirteen submissions, seed collisions (including
source-pilot seeds), ancestry/depth checks, RNG inheritance, preserved
parents, analysis selection, duplicate/wrong-N rejection and partial-failure
records. It also runs the existing eight-stream campaign integration check.
Python tests exercise both eight- and 24-stream analysis paths, separate
old8/fresh16 bootstraps, action diagnostics, subset sizes and charge overlays.
