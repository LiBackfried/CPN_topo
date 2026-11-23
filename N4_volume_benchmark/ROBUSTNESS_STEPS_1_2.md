# L90/L120 post-processing: steps 1 and 2

## Reported submissions

On 2026-11-21 the user reported the following successful `sbatch` submissions.
Both results were copied on 2026-11-23, with analysis and record completion
markers. See [the completed review](ROBUSTNESS_REVIEW_20261123.md). Remote
Slurm status has not been independently checked. These jobs perform the
robustness checks below; they do not add
autocorrelation-time estimation or source-beta thermalization pilots.

| Volume | Analysis job | Records/logs under that volume's result root | Expected output directory |
| --- | --- | --- | --- |
| L90 | 22974797 | `robustness_submit.e9FfqB/` | `robustness_steps12_22974797/` |
| L120 | 22974798 | `robustness_submit.Eh36vA/` | `robustness_steps12_22974798/` |

The UBELIX result roots are
`/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L90_res` and
`/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res`.
Machine-readable submission records are in
[L90](../N4_L90_res/reported_robustness_jobs_20261121.tsv) and
[L120](../N4_L120_res/reported_robustness_jobs_20261121.tsv).

## Submission instructions

Run from the UBELIX repository root after syncing the new Python driver,
the two shell scripts, and their existing imported analysis modules:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N4_volume_benchmark/submit_robustness_ubelix.sh
```

This submits **two independent analysis jobs**, one per volume, each with
one CPU, 16 GB and a 24-hour time limit. The time limit is an allocation
request, not a measured runtime prediction. No executable rebuild or new
simulation is needed. The jobs read the existing raw data, including all
continuation parents. The scripts never write to simulation directories.

Submit just one volume with an argument `90` or `120`. Alternatively submit
the batch worker directly with `sbatch` (never execute the worker with bash):

```bash
sbatch N4_volume_benchmark/robustness_L90_L120_ubelix.sh 90
sbatch N4_volume_benchmark/robustness_L90_L120_ubelix.sh 120
```

The submission helper prints IDs and log paths. Each volume writes fresh
`N4_L<L>_res/robustness_steps12_<ANALYSIS_JOB>/` and
`robustness_record_<ANALYSIS_JOB>/` directories. Submission logs live in
`robustness_submit.<random>/`. A `completed` marker indicates both checks
finished; partial output without that marker must not be treated as complete.
On retry, submit a fresh job to get a fresh output directory.

| Volume | NS leaf jobs (groups 1, 2, 3) | Cumulative updates/stream | MCMC job | Target beta |
| --- | --- | ---: | --- | ---: |
| L90 | 22810844, 22810845, 22810846 | 210,000 | 22635137 | 0.95 |
| L120 | 22885157, 22904262, 22904264 | 300,000 | 22780263 | 1.0 |

Each NS group has four independently seeded streams with 50 live points,
source beta 0.7 and 6L² proposals/update. The loader follows `parent_run`,
checks repeated checkpoint boundaries and removes the repeated rows. The
MCMC reference has three chains; discard measurements through MC step
20,000. Block sizes below count stored measurements (10 MC steps each).
The worker checks campaign markers/settings, then Python checks the raw
segments, N=4 logs, seeds, alignment and cumulative depth.

## Step 1: bin and block robustness

Use the full twelve-stream NS ensemble and all nine combinations of
8/16/32 action bins and MCMC block sizes 128/512/1024. Use MCMC quantiles
over the central 99% of its action range. Freeze these boundaries across
block choices and subsets. The edges use complete 128-measurement blocks,
matching the original comparison; longer block choices discard their own
incomplete per-chain tails. All bins share the full-ensemble common NS
energy cutoff, which must lie below the comparison range.

The NS calculation uses 200 whole-stream bootstrap draws, each re-merged
and reweighted. One bootstrap evaluates all three bin choices together.
MCMC errors use the existing delete-complete-block jackknife; blocks never
cross chain boundaries. These estimates require sufficiently long blocks.

Start reading `step1/grid.csv`. Each `bins<B>_block<K>/` contains the familiar
`bins.csv`, `summary.csv`, and `comparison.png`, plus:

- `covariance.csv`: the full G0/Gk residual covariance, including cross-bin
  and cross-correlator correlations; sum independent NS and MCMC covariances.
- `joint.json`: observed maximum absolute standardized residual, an approximate
  centered-bootstrap joint p diagnostic and simultaneous 95% critical value.
- `simultaneous_intervals.csv`: residual intervals using that common critical value.

The joint null uses 1,000 whole-MCMC-block draws and independent centered
NS-bootstrap draws. Resample each multivariate block intact. The maximum
runs over **both correlators and all bins in that configuration**, avoiding
covariance inversion and accounting for selecting the largest bin residual.
Quantile edges are treated as fixed; their estimation uncertainty is not
propagated. These are approximate bootstrap diagnostics, with only twelve
independent NS streams and 200 NS replicates. The nine grid rows are correlated:
inspect their pattern; the smallest p is not an omnibus test across the grid.
This check cannot establish absence of constrained-sampling bias.

## Step 2: groups and stream influence

Use **32 bins and blocks of 512** as the fixed reference for this check.
`streams.csv` maps zero-based stream IDs to group, leaf directory and RNG seed.

- `step2/observables.csv`: weighted action density, xi_L_squared,
  susceptibility, log_Z_ratio, G0 and Gk for full12, the three independent
  four-stream groups, and all twelve eleven-stream leave-one-out subsets.
  Full/group errors are whole-stream bootstrap standard deviations.
  MCMC means/errors are included where an observable has a direct reference.
- `step2/group1_*`, `group2_*`, `group3_*`: conditional-correlator comparisons
  against the same MCMC reference, with plots, covariance and joint diagnostics.
- `step2/group_pairs.csv`: pairwise differences of independent four-stream
  groups, including conditional correlators. Their SE combines the two NS
  errors only; the shared MCMC reference cancels. Individual standardized
  entries are descriptive and are not corrected for searching this table.
- `step2/leave_one_out_bins.csv`: conditional correlator changes after dropping
  each stream, plus the residual against the shared MCMC reference.
- `step2/leave_one_out_observables.png` and `leave_one_out_bins.png`: influence
  plots normalized by the corresponding **full NS bootstrap SE**.

Every subset is re-merged with its actual live-point count (200 for groups,
550 for leave-one-out, 600 for full12). Subsets retain the same common energy
cutoff to keep support fixed. Leave-one-out rows report deterministic influence,
not a new SE or a significance test: their `bootstrap_se` fields are blank.
They overlap strongly with full12 and one another. Four-stream bootstrap
errors are especially coarse; a group difference is a follow-up signal,
not proof that a stream is invalid.

Keep all twelve streams in the primary result. Use these outputs to decide
whether the isolated conditional residual persists under bin/block choices
or concentrates in one seed/group. This prepares the choice of a separate
constrained-mixing validation campaign; it does not extend production depth.

The records include input IDs/paths, source hashes, revision/status, Python
versions, bin edges and numerical settings. Change the default scratch root
with `NS_SCRATCH=/absolute/path`. For a later precision check, set
`ROBUSTNESS_BOOTSTRAP` or `ROBUSTNESS_JOINT_DRAWS` when submitting; increasing
only joint draws does not create additional independent NS information.
