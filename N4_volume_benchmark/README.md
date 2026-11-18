# CP³ volume and reweighting benchmark on UBELIX

For the seven-point beta scan comparing L22 with the 8,664-proposal L38
ensemble, including available direct MCMC references, see
[VOLUME_BETA_SCAN.md](VOLUME_BETA_SCAN.md). Submit from the repository with
`bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh`.

The prepared L66 campaign, runtime measurements, submission commands and
analysis-output convention are documented in [N4_L66_res/README.md](../N4_L66_res/README.md).
It uses 26,136 proposals per update and saves analysis in repository `N4_L66_res/`.

Run nested sampling at `N=4`, `beta=0.7`, `theta=0` and reweight each lattice
separately to `beta=0.8, 0.9, 1.0`. Start with a 100-update timing pilot at
`L=22, 38, 66, 90, 120`. Extend `L=38` first to measure reweighting depth on a
larger volume. Use those results and same-volume target MCMC to decide which
larger NS runs are worth scheduling.

## What the L=22 data say

The 25 local UBELIX runs `750–774` have 50 live points and 50,000 NS updates
each. Their simulation-loop wall time was 0.0388–0.0475 s/update, with median
0.0442 s/update, from the start/end times in `log.dat`. This is the cluster
baseline for the production kernel. The five-update WSL smoke test used a
different beta and stochastic-update count.

Scanning these 25 chains with `scan_depth.py` and comparing to the deepest
shared energy range gives the following. The 99% depths count energy-ranked
dead points divided by 25. The tested prefixes in the last column had less
than 1% of their observed target mass in the final tenth of the shared ranks.
Their point estimates for action density, `xi_L_squared`, and `chi_topological`
were close to the full-chain estimates. These are depth diagnostics. Accuracy
and sampling error still need a separate check, especially for topology.

| Target beta | Depth at 99% mass | Action density at 99% mass | First tested prefix with <1% edge mass |
| --- | ---: | ---: | ---: |
| 0.8 | 2,311 | 0.67774 | 3,000 |
| 0.9 | 5,883 | 0.57924 | 8,000 |
| 1.0 | 9,872 | 0.50889 | 12,500 |

At `beta=1.0`, a 10,000-update prefix still put about 14% of its observed
target mass in the final tenth of the common ranks. Reproduce the depth scan
from the repository root with the local data next to the checkout.

```bash
python N4_volume_benchmark/scan_depth.py ../data_N4_UBELIX \
    --updates 100 500 1000 2000 3000 5000 6000 8000 10000 12500 15000 > L22_depth.csv
```

## Slurm pilot and planning estimates

See [CP³ nested-sampling kernel timings](PERFORMANCE.md) for the optimized
kernel's measured wall time at all five volumes. Run
`bash N4_volume_benchmark/time_ubelix.sh` on UBELIX to submit matched timing
pilots and generate a report. The L⁴ model below describes the original kernel.

Keep `epyc2`, `gratis/job_gratis`, one task and one CPU per chain, and
`--mem-per-cpu=512M` for the pilot. Use four independent chains per volume
and preserve 50 live points, four microcanonical sweeps, `num_norm=1`, and
the L=22 cooling settings. Start with `3 L²` stochastic proposals per NS
update, keeping the rounded 1,500 at `L=22`. The pilot uses `num_ns_meas=101`.

The original stochastic-update loop recomputed the energy over all `L²`
sites after every proposal. With `3 L²` proposals, that work grows as `L⁴`.
The first timing estimate is `0.05 s × (L/22)^4` per NS update, rounded up
from the observed L=22 maximum. The first depth estimate scales the L=22
screening prefixes (3k, 8k, 12.5k) by `(L/22)^2` at fixed live-point count.
This assumes comparable energy large-deviation behavior per site. The
result is a screening budget whose adequacy may change with volume and beta.
Times in the last three columns are projected hours **per chain**.
At fixed depth, `updates / num_live_pts` sets the expected `-log X` per
stream. Adding independent chains helps precision at the sampled depth.
Increasing the live-point count per chain requires more updates to reach
the same expected depth.

| L | Stochastic proposals | Pilot `--time` | Model s/update | β 0.8 updates, hours | β 0.9 updates, hours | β 1.0 updates, hours |
| ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 22 | 1,500 | `00:10:00` | 0.05 | 3k, 0.04 h | 8k, 0.11 h | 12.5k, 0.17 h |
| 38 | 4,332 | `00:10:00` | 0.45 | 9k, 1.1 h | 23.9k, 3.0 h | 37.3k, 4.6 h |
| 66 | 13,068 | `00:30:00` | 4.05 | 27k, 30 h | 72k, 81 h | 112.5k, 127 h |
| 90 | 24,300 | `01:00:00` | 14.0 | 50.3k, 196 h | 133.9k, 521 h | 209.2k, 814 h |
| 120 | 43,200 | `03:00:00` | 44.3 | 89.3k, 1,098 h | 238.1k, 2,927 h | 372k, 4,573 h |

For a 100-update pilot the model predicts roughly 7 CPU-hours across the
20 chains, excluding initialization and filesystem overhead. Use the
longest elapsed time among concurrent chains for wall-time sizing. UBELIX
documents a 96-hour limit for `job_gratis`. On this model `L=66, beta=1.0`
already crosses it, as does every `L=90` and `L=120` target. Multiple segments
can accommodate the wall-time limit while the total CPU cost stays the same.
[UBELIX accounts, partitions and QoS](https://hpc-unibe-ch.github.io/runjobs/partitions/)

From the UBELIX repository root, build the existing N=4 executable if needed,
then submit the pilots. Check the first jobs' timing and memory before
committing the larger allocations.

```bash
bash N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh
sbatch --time=00:10:00 N4_volume_benchmark/run_ubelix.sh 22
sbatch --time=00:10:00 N4_volume_benchmark/run_ubelix.sh 38
sbatch --time=00:30:00 N4_volume_benchmark/run_ubelix.sh 66
sbatch --time=01:00:00 N4_volume_benchmark/run_ubelix.sh 90
sbatch --time=03:00:00 N4_volume_benchmark/run_ubelix.sh 120

sacct -j JOB_ID --format=JobID,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,MaxRSSTask,ExitCode
```

Each job writes to
`/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L<L>/job_<ID>/`.
Each `run_*` has `timing.txt` (elapsed, CPU and max RSS), `node.txt` (host and
CPU model), `stdout.log` (initialization and simulation CPU time), and the
usual measurements and checkpoints. `NS_SCRATCH` can override the absolute
base directory. The launcher takes the update count as its second argument
and sets `num_ns_meas` to that count plus one. `--ntasks` overrides the chain
count. Fresh jobs can override `NS_STOC`, `NS_INIT_SWEEPS`, and
`NS_INIT_SPACING` for sensitivity runs.

For the next allocation, fit time per update from different-length segments
on comparable CPUs. Use the slowest observed segment rate near the desired
cutoff, add initialization/copy overhead and about 30% time headroom. For
example, choose `updates_per_segment` so that
`1.3 × (overhead + updates_per_segment × slow_rate)` fits the request and
the QoS limit. Size `--mem-per-cpu` from the largest per-chain RSS with
headroom. The 50 live configurations reside on disk. Measure their size and
the size of `topo.dat` when budgeting scratch across segments. On L=22 the
measurements and acceptance log total about 75 MB per 50,000 updates and the
checkpoint about 2.3 MB per chain.

## Measure depth before scaling production

For the independent L=38 comparison at β=1.0, run
`bash N4_volume_benchmark/fresh_L38_12_ubelix.sh` on UBELIX. It submits three
fresh four-chain jobs with 35,000 updates per chain and job-derived seeds.
It uses the saved executable from job `22120845` and prints two commands
with the actual job directories to produce `N4_L38_res/L38_depth_fresh12.csv`
and `N4_L38_res/L38_depth_combined16.csv`. The 16-chain scan follows the original job's
continuation history. Use `NS_SCRATCH` if the original job lives under a
different scratch base.

### L=38 correlation-length cross-check at β=1.0

`scan_depth.py` now includes `mean_G0` and `mean_Gk` with stream-bootstrap
errors. Both correlators are already stored in `dati.dat`. Reanalyze the
existing 16-chain sample and the direct MCMC job to get their separate
estimates. In the Bash block below, set `fresh_jobs` to the three job
directories printed for the original 12-chain campaign.

```bash
module load Python SciPy-bundle matplotlib
scratch="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}"
base="$scratch/ns_N4_beta0p7_volume_benchmark/L38"
fresh_jobs=("$base/job_JOB1" "$base/job_JOB2" "$base/job_JOB3")
mkdir -p N4_L38_res
python N4_volume_benchmark/scan_depth.py "${fresh_jobs[@]}" "$base/job_22120845" \
    --updates 30000 --targets 1.0 --bootstrap 200 > N4_L38_res/L38_correlators_combined16.csv

mcmc="$scratch/mcmc_38_N4_beta1p0_3x100k/job_22121710"
python utils/plot_mcmc.py "$mcmc" --burn-in 20000 \
    --output N4_L38_res/mcmc_correlators_burn20000
awk -F, '$1=="pooled" && $2==128 && ($5=="mean_G0" || $5=="mean_Gk" || $5=="xi_L_squared")' \
    N4_L38_res/mcmc_correlators_burn20000/binning.csv
```

From the UBELIX repository root, submit the proposal-count sensitivity run:

```bash
bash N4_volume_benchmark/fresh_L38_2xstoc_ubelix.sh
```

This uses the saved executable from job `22120845` to start twelve
independent chains at source β=0.7 with 8,664 stochastic proposals per NS
update and 35,000 NS updates per chain. It requests 45 minutes for each of
three four-chain jobs. After completion, run the analysis block printed by
the script. It compares 30,000 and 35,000 updates at β=1.0 and writes
`N4_L38_res/L38_depth_2xstoc12.csv`. Compare the 35,000-update rows from
the two NS scans with the pooled MCMC row for each observable. The two NS
proposal counts define separate ensembles.

#### Compare correlators at matched action density

Use the files from both NS ensembles and MCMC job `22121710`. The three
doubled-proposal jobs are `22320950`, `22320951`, and `22320952`, as supplied
by the user on 2026-11-18. From the UBELIX repo root, submit the analysis:

```bash
sbatch N4_volume_benchmark/analyze_L38_action_bins_ubelix.sh 22320950 22320951 22320952
```

The batch analyzes the two NS settings separately against the same MCMC
reference. It uses 35,000 NS updates per chain, reweights to β=1.0, and
uses the 20,000-step MCMC burn-in cut with 128-measurement jackknife blocks.
The 16 bin intervals are set by MCMC quantiles over its central 99%
of sampled action density and are held fixed during resampling. Each NS
bootstrap draw remerges and reweights whole streams.

Pull `N4_L38_res/action_bins/` after the analysis finishes. Both `stoc4332/`
and `stoc8664/` contain `comparison.png`, `bins.csv` and `summary.csv`.
`bins.csv` reports the target mass and conditional correlator means for
each method and bin. In `summary.csv`, `within_bin` combines the conditional
differences using the average bin masses, while `bin_weight` combines the
mass differences using the average conditional means. These terms sum to
the NS-minus-MCMC difference over the common range after renormalizing
there. Add `outside_range_effect` to recover the difference over the full
sampled range. The three terms are correlated. Check the dependence on bin
width with `--bins` if steep variation inside a bin could explain a
conditional difference.

To repeat the comparison with 32 bins, submit:

```bash
sbatch N4_volume_benchmark/analyze_L38_action_bins_ubelix.sh 22320950 22320951 22320952 32
```

Pull `N4_L38_res/action_bins_32bins/` after completion. Its `stoc4332/` and
`stoc8664/` subdirectories each contain `comparison.png`, `bins.csv` and
`summary.csv`. Compare the `within_bin` and `bin_weight` terms with the
16-bin summaries in `N4_L38_res/action_bins/`. Omitting the final bin-count
argument uses the original 16-bin analysis and output paths.

#### Add twelve more 8,664-proposal chains and analyze all ensembles

From the repository root on UBELIX, run:

```bash
bash N4_volume_benchmark/fresh_L38_2xstoc_ubelix.sh --more
```

This submits three four-chain jobs with 35,000 NS updates per chain, source
β=0.7, and 8,664 proposals per update. It uses job-derived seeds and the
saved executable from job `22120845`. It also submits an analysis batch
with an `afterok` dependency on all three new jobs. The existing doubled
jobs are `22320950`, `22320951` and `22320952`.

The helper prints and records a unique output directory such as
`N4_L38_res/extra8664.ABCDEF/` inside the repository. The simulation files
go to `$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L38/job_<ID>/` with the
usual scratch default. All CSVs, plots, and the analysis Slurm log go to
the repository output directory. It contains:

- `new_jobs.tsv`, `analysis_job_id.txt` and `analyze_command.txt` for the
  submitted job IDs, data locations and analysis retry command.
- `depth_fresh12.csv`, `depth_previous12.csv`, `depth_combined24.csv` and
  `depth_baseline16.csv`, each comparing 30,000 and 35,000 updates at
  target β=0.8, 0.9 and 1.0 with 200 stream-bootstrap replicates.
- `action_bins32/fresh12/`, `previous12/`, `combined24/` and `baseline16/`,
  each with `comparison.png`, `bins.csv` and `summary.csv` against the
  same direct MCMC sample at β=1.0.
- `mcmc_burn20000/` with the MCMC histories, histogram, and binning analysis
  including `mean_G0` and `mean_Gk`.
- `completed`, created after every analysis succeeds.

The first three NS analyses use 8,664 proposals. `baseline16` uses the
four original chains from leaf job `22120845` and the twelve from
`22133588`, `22133589` and `22133590`, each with 4,332 proposals. The
combined doubled-proposal estimate uses 24 independent chains. The
new batch is also analyzed alone to check its agreement with the previous
twelve chains. Each simulation job requests 45 minutes, and the dependent
analysis job requests two hours on one CPU.

#### Increase L=38 to 12,996 stochastic proposals per update

To test a further increase of 4,332 proposals per NS update, run:

```bash
bash N4_volume_benchmark/fresh_L38_2xstoc_ubelix.sh --stoc12996
```

The helper submits twelve independent fresh chains in three four-chain
jobs at source β=0.7, with 12,996 proposals per NS update and 35,000 NS
updates per chain. Each simulation job requests one hour. It uses the
saved executable from job `22120845` and independent job-derived seeds.
A dependent two-hour analysis job starts after all three simulations
finish successfully.

All analysis outputs and submission records go into a new directory
`N4_L38_res/stoc12996.XXXXXX/` in the repository. Simulation data goes to
the usual scratch base. The analysis produces:

- `depth_stoc12996_12.csv` for the new twelve chains.
- `depth_stoc8664_24.csv` for the existing doubled-proposal jobs `22320950`,
  `22320951`, `22320952`, `22583507`, `22583508` and `22583509`.
- `depth_baseline16.csv` for the sixteen 4,332-proposal chains.
- `action_bins32/` with the three corresponding comparisons against direct
  MCMC job `22121710`, and `mcmc_burn20000/` with its binning results.

Each depth scan compares 30,000 and 35,000 cumulative updates at target
β=0.8, 0.9 and 1.0 with 200 stream-bootstrap replicates. The 32-bin
comparisons use target β=1.0. The NS proposal settings remain separate
ensembles in all analyses. Pull the printed repository output directory
when its `completed` marker appears. Use the saved `analyze_command.txt`
to retry the analysis if needed.

### Volume and depth plan

1. **Extend L=38 first.** Inspect prefixes around 5k, 10k, 20k, and 35k–40k
   cumulative updates per chain, adapting the next segment length to actual
   timing and coverage. For example, after a successful 100-update L=38 job,
   add 4,900 updates. Use the same task count as the parent and point to the
   last successful segment for each further continuation.

   ```bash
   base=/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark
   sbatch --time=01:15:00 N4_volume_benchmark/run_ubelix.sh 38 4900 "$base/L38/job_<pilot_ID>"
   ```

   Each continuation copies the completed parent's executable and all
   checkpoint files into its new job directory before `srun`. Parent outputs
   are read-only inputs. Failed or timed-out segments lack a `completed`
   marker and cannot serve as parents. Keep the ancestor directories while
   using the leaf. Preserve their relative layout if moving results to another
   filesystem. A branch shares its parent's seed and is part of the same stream
   for analysis.

2. **Scan prefixes at every target.** Use a single volume per command. Pass
   the latest job directory for each group of independent chains. The scanner
   follows `parent_run` links, drops the repeated measurement at each segment
   boundary, and merges streams only over the energy range they all cover.
   It compares each requested prefix with the deepest shared prefix.

   ```bash
   module load Python SciPy-bundle matplotlib
   python N4_volume_benchmark/scan_depth.py "$base/L38/job_<leaf_ID>" \
       --updates 100 1000 2500 --bootstrap 200 > L38_depth.csv
   ```

3. **Use coverage and stability together.** If the 99% target quantile hugs
   the common low-energy edge or the last tenth of ranks carries appreciable
   weight, extend the chains. Use 1% edge mass as an initial screening
   threshold. Require agreement across successive deeper prefixes in mean
   action density, `xi_L_squared`, `chi_topological` and `log_Z_ratio`. For
   a production depth decision, choose physics tolerances and use the 95th
   percentile of paired bootstrap shifts. One starting budget for truncation
   bias is 10% of the desired production statistical error, following the
   existing L=22 prefix study. The bootstrap resamples whole streams and
   uses the same draws at every depth. Four streams are for screening. Repeat
   with more independent seeds before estimating production precision.

   The CSV also reports `log_missing_target_fraction_bound`, based on the
   estimated remaining source mass `X` and the theta-zero action floor
   `H >= 0`. For these higher betas, the unseen contribution to `Z_target /
   Z_source` is at most `X` given the shrinkage estimate. A bound near zero
   in log space is uninformative. A small observed edge mass alone cannot
   exclude unseen weight. Look at concentration by stream, and check Q-sector
   coverage and both acceptance rates near the target band. Quadrature and
   stream-weight ESS measure weight concentration. Precision comes from
   agreement across independent streams and ensembles. Compare a fresh
   `NS_STOC=2 × baseline` run and longer source burn-in/live-point spacing
   at L=38 before transferring settings. A spacing or proposal-count change
   should be a separate ensemble in the scan.
   [Nested-sampling diagnostics](https://academic.oup.com/mnras/article/483/2/2044/5184484)

4. **Calibrate the energy range and compare volumes.** Run independent direct
   MCMC at `0.7, 0.8, 0.9, 1.0` on L=38, then on any larger volume under
   consideration. The [L=38, beta=1.0 MCMC setup](mcmc_38_N4_beta1p0_3x100k/README.md)
   is ready to submit. For the other ensembles, change the volume, beta and
   seeds, and keep theta and observable definitions fixed.
   Estimate equilibration and autocorrelation separately for energy and Q.
   Check that the NS common cutoff extends below the low-energy tail of the
   direct target histogram (start with its 1st percentile) and compare the
   reweighted action, correlation length and topology within errors. Inspect
   Q histories across seeds before interpreting a small susceptibility.
   Compare `xi_L/L`, `chi_topological`, and action density across volumes
   at fixed target beta only after passing these checks at each volume.

Use the measured `L=38` depth and runtime to re-budget `L=66`. For `L=90`
and `L=120`, prioritize direct target MCMC for the volume test if the pilots
confirm the projected cost of deep `beta=0.7` NS. If reweighting itself is
required at those volumes, benchmark closer source betas or a validated
faster constrained-update kernel before scheduling full chains. Changing the
source beta changes the prior and requires independent runs and analysis.
