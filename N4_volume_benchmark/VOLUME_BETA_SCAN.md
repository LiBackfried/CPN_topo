# N=4: L22/L38/L66 volume comparison over beta

To include L66, run from the UBELIX repository root:

```bash
INCLUDE_L66=1 bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

This submits **four analysis jobs**: the L22, L38 and L66 scans, followed by
their dependent comparison. All outputs go to a new repository directory
`N4_L66_res/volume_scan.XXXXXX/`, with per-volume `L22/`, `L38/`, `L66/`
subdirectories. Simulation data remain on scratch. No new simulation is run.

If a completed seven-beta L22/L38 scan already exists, pass it to reuse its
two analysis subdirectories and submit only L66 plus the comparison:

```bash
INCLUDE_L66=1 bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh \
    "$PWD/N4_L38_res/volume_scan.ACTUAL_COMPLETED_SUFFIX"
```

Both input subdirectories must contain completed `beta_scan.csv` files.
The reused directories are copied into the new output; their inputs are
preserved, and `settings.txt` records the source directory. Reused jobs are
identified in `jobs.tsv`. This option does not resume unfinished bootstraps.

L66 uses the **12 completed streams** in NS jobs `22587433`, `22587434`,
`22587435`: source beta=0.7, theta=0, 50 live points, **26,136 stochastic
proposals per update**, **110,000 updates per stream**. Each job has four
streams. Copied earlier L66 depth scans already cover all seven betas; this
option integrates that dataset into the shared analysis, adds the normalized
weight overlays, and directly bootstraps xi and xi/L consistently with the
new L22/L38 scans. It retains full depth for the reweighting to beta=1.0.

The L66 MCMC reference is beta=0.9, three chains in job `22587511` under
`/scratch/network/users/lb25v444/out_data/mcmc_66_N4_beta0p9_3x100k/`.
It is included when present, or can be overridden with `MCMC_L66_DIR`.
The same burn-in and block-size settings apply to all MCMC references.

L66 defaults request **8 GiB / four hours**, configurable with
`L66_SCAN_MEM` and `L66_SCAN_TIME`. These are provisional resource requests.
The three-volume plots use circles for L22, triangles for L38 and squares
for L66. NS remains crimson and MCMC royalblue. The difference table includes
all three volume pairs. Signed xi-squared values are preserved; undefined
square roots are marked `?66` on the xi/L plot rather than replaced with zero.
`xi_status` and the finite-bootstrap fractions record undefined estimates
or errors. Prior L66 low-beta xi-squared results at 0.7 and 0.75 are unresolved;
see [RESULTS_REVIEW.md](../N4_L66_res/RESULTS_REVIEW.md).

Without `INCLUDE_L66=1`, the original two-volume workflow below is unchanged.

From the UBELIX repository root, run:

```bash
bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

The helper submits three Slurm analysis jobs: L22, L38, then a comparison job
depending on successful completion of both scans. It reads existing simulation
measurements. No simulation checkpoints or raw measurements are modified.
All outputs and Slurm logs go to the printed, unique directory
`N4_L38_res/volume_scan.XXXXXX/` **inside the repository**.

The selected NS ensembles are:

| L | Source beta | Proposals per NS update | Independent chains | Depth per chain |
|---|---|---|---|---|
| 22 | 0.7 | 1,500 | 100 selected from 800 | 50,000 updates |
| 38 | 0.7 | 8,664 | 24 | 35,000 updates |
| 66 (optional) | 0.7 | 26,136 | 12 | 110,000 updates |

L22 selects 100 run directories without replacement from the 800 candidates
listed in `sh_files/analyze_N4_L22_ubelix.sh`. Selection is uniform using
`STREAM_SELECTION_SEED=20261118` and sorted candidate paths, before reading
measurements. It is independent of measured observables and reproducible
across retries. Only selected streams are loaded and bootstrapped.
The launcher checks that all candidate files exist before starting the scan.
`L22_MAX_STREAMS` changes the selected count (2 to 800). L38 uses four chains from each job
`22320950`, `22320951`, `22320952`, `22583507`, `22583508`, `22583509`.
The scans require the selected chains to be complete, independently seeded,
N=4, theta=0, and to share settings within each volume. They use the full
available shared energy range (the largest final action density is the common
lower cutoff). Outputs record this cutoff and the retained point count.

Each ensemble is evaluated at beta **0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00**.
Reweighting uses the existing canonical-source convention and
`H = 2*N*L^2*epsilon`, hence a factor `exp[-(beta-0.7)*H]` in the quadrature.
The source-beta point is included. N is set explicitly to 4 in the analysis.
Final-cooling measurements retain the simulation's cooling settings.

## MCMC references

The known L38 reference is the three-chain beta=1.0 job `22121710` under
`/scratch/network/users/lb25v444/out_data/mcmc_38_N4_beta1p0_3x100k/`.
It is included when present. L22 looks for one complete three-chain job under
`/scratch/network/users/lb25v444/out_data/mcmc_22_N4_beta0p7_3x1M/`.
If no unique job is found, the NS comparison still completes and
`mcmc_status.txt` explains the missing L22 reference.

To specify the actual L22 job, use its real directory:

```bash
MCMC_L22_DIR=/scratch/network/users/lb25v444/out_data/mcmc_22_N4_beta0p7_3x1M/job_ACTUAL_ID \
    bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

`MCMC_L38_DIR` similarly overrides the known L38 directory. Explicit overrides
must be complete fresh three-chain N=4 jobs, with theta=0 and cooling step 50.
MCMC markers are placed at their simulated betas; they are not reweighted to
the rest of the grid. Thus beta=0.7 (L22, if available) and beta=1.0 (L38) are
direct same-volume NS/MCMC checks. A matched-volume MCMC comparison at every
beta would require additional direct MCMC data or a separately validated
MCMC reweighting study.

MCMC defaults discard measurements at stored MC step <=20,000 and use bins
of 128 measurements for pooled blocked jackknife errors. The complete powers
of two binning scan is saved for checking the error plateau, particularly for
topology. `MCMC_BURN_IN` and `MCMC_BLOCK_SIZE` can override these defaults.
Errors for MCMC xi and xi/L use the delta method from the xi-squared error.

## Outputs

- `L22/beta_scan.csv`, `L38/beta_scan.csv`: point estimates, whole-stream
  bootstrap standard errors, finite-bootstrap fractions, and support diagnostics.
- `L22/inputs.json`, `L38/inputs.json`: exact selected inputs, candidate count,
  selection seed, settings, depth, bootstrap seed. `selected_runs.txt` records
  the selected paths before expensive I/O and bootstrap.
- `L22/normalized_weights_single_run.png` and `.pdf`, and the same under `L38/`:
  one independently seeded NS stream per volume, overlaying all seven beta
  curves. Each curve is normalized to sum to one over the full single stream,
  using that stream's own live-point count. The first selected stream is used
  deterministically, and is identified in the title and accompanying JSON.
  `_log.png`/`.pdf` variants show base-10 log weights, including underflowed
  tails. The full weights, log weights, ranks and action densities are saved
  in `normalized_weights_single_run.npz`; no points are thinned. Displayed x
  ranges contain at least 99.99% of each curve's mass. These single-stream
  diagnostics are separate from the common-support merged observable estimates.
- `volume_comparison.csv`: both volumes and available MCMC references, with
  errors uniformly named `*_se` (bootstrap for NS; blocked jackknife for MCMC).
- `volume_shifts.csv`: differences for each available volume pair, beta and
  common observable, with independent-volume statistical errors added in
  quadrature. `L_small`, `L_large` identify the pair; L38-minus-L22 legacy
  columns are retained for that pair.
- `ns_mcmc_comparison.csv`: NS minus direct MCMC at matching volume/beta,
  including combined statistical errors; written when references are available.
- `volume_dependence.png` and `.pdf`: action density, xi/L, topological
  susceptibility, G0, Gk, xi-squared. NS is **crimson**, MCMC **royalblue**;
  circles/solid lines identify L22, triangles/dashed lines L38.
- `coverage_diagnostics.png`: edge mass, stream-weight ESS, quadrature ESS.
- `mcmc_L22_binning.csv`, `mcmc_L38_binning.csv` when raw references exist.
- `jobs.tsv`, `resources.tsv`, `settings.txt`, `comparison_settings.json`,
  `mcmc_status.txt`, job logs.

The same weight, NS and MCMC outputs extend to `L66/` and `mcmc_L66_binning.csv`
when the third volume is enabled. Existing three-volume plots can be rebuilt
with the usual `plot_volume_betas.py` invocation plus
`--l66 "$result_dir/L66/beta_scan.csv"` and, when available,
`--mcmc-l66 /scratch/network/users/lb25v444/out_data/mcmc_66_N4_beta0p9_3x100k/job_22587511`.

NS errors resample whole independent chains, remerge by energy, and recompute
weights in each replicate. The same replicate selection is shared across all
seven betas within a volume. The two volumes have different stochastic proposal
counts, so interpreting their difference as a physical volume effect also
depends on the existing constrained-chain mixing checks. Statistical errors do
not include possible mixing or finite-depth biases. Check edge mass and stream
weight concentration before interpreting a reweighted point; quadrature ESS is
not an independent sample count. The missing-target-mass bound is conditional
on the expected NS shrinkage estimate and can be loose. Finite-bootstrap
fractions flag undefined square roots of negative xi-squared; such errors are
left undefined rather than discarding those replicates.

Defaults are 200 stream bootstraps, L22 16 GB / 4 hours for 100 streams,
L38 8 GB / 4 hours,
comparison 16 GB / 2 hours. These are resource requests, not timing measurements.
The default L22 analysis loads 100 full streams and is the expensive stage.
Override `N_BOOTSTRAP`, `BOOTSTRAP_SEED`, `L22_SCAN_TIME`, `L38_SCAN_TIME`,
`L22_SCAN_MEM`, `L38_SCAN_MEM`, `COMPARISON_SCAN_MEM`, `COMPARISON_SCAN_TIME`
as needed. Memory settings use Slurm units, e.g. `16G`. The resource requests
are provisional; the smaller L22 ensemble reads one eighth of the former
800-stream data volume. Selecting fewer independent streams trades statistical
precision for lower analysis cost, while preserving full depth and all betas.
For example, explicitly request the reduced setup with:

```bash
L22_MAX_STREAMS=100 L22_SCAN_MEM=16G L22_SCAN_TIME=04:00:00 \
    bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

For a full 800-stream analysis, increase the memory allowance explicitly,
e.g. `L22_MAX_STREAMS=800 L22_SCAN_MEM=64G`; check the memory-time policy below.
`VOLUME_DATA_ROOT` changes the scratch base for all input families.

### Submission rejected with MaxMemoryRunMinsPerUser

This reason refers to the per-user memory-times-requested-runtime limit,
including running jobs. The original L22 request of 64 GiB for 24 hours
was rejected on UBELIX. The revised 100-stream request uses 16 GiB for four
hours, reducing this budget from 1,536 to 64 GiB-hours. This is a submission
budget adjustment, not a measured four-hour completion time or a guarantee
of acceptance under the user's current limit.

An older launcher accepts a time override, but selecting fewer streams
requires updating all three files `submit_volume_beta_scan_ubelix.sh`,
`volume_beta_scan_ubelix.sh`, and `scan_volume_betas.py`. A time-only retry
of the older 800-stream setup keeps its 64 GiB memory allowance:

```bash
L22_SCAN_TIME=04:00:00 bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

To inspect the actual live policy and other jobs consuming the allowance:

```bash
sacctmgr show qos job_gratis format=Name,MaxTRESRunMinsPU%80
squeue -u "$USER" -o "%.18i %.10T %.12m %.12l %j"
```

If this is still rejected, use those outputs to size the request; the error
alone does not reveal the numerical cap. Waiting helps when other running
jobs consume the allowance. Lowering RAM requires checking actual peak usage;
lowering the time limit can cause a timeout. The beta scan currently writes
its CSV after all bootstrap replicates complete, so a timeout requires
repeating that scan. `jobs.tsv` records accepted submissions if the helper
fails after submitting only part of the workflow.

References: [Slurm per-user TRES runtime limits](https://slurm.schedmd.com/sacctmgr.html#OPT_MaxTRESRunMinsPU)
and [UBELIX free-tier resource accounting](https://knowit.unibe.ch/en/docs/hpc/costs/freetier/).

### srun rejects conflicting memory environment variables

The synced logs in `N4_L38_res/volume_scan.vK9cR3/` show that scans
`22603540` and `22603541` failed before Python started:
`SLURM_MEM_PER_CPU, SLURM_MEM_PER_GPU, and SLURM_MEM_PER_NODE are mutually exclusive`.
The comparison submission was `22603542`, dependent on both scans succeeding.
The launcher now clears inherited memory settings before `sbatch`; the worker
also clears per-CPU/GPU settings before `srun`, retaining the per-node memory
setting supplied by its own allocation.

For this failed workflow, after updating the two shell scripts on UBELIX:

```bash
sacct -j 22603540,22603541,22603542 --format=JobID,State,ExitCode
scancel 22603542
unset SLURM_MEM_PER_CPU SLURM_MEM_PER_GPU SLURM_MEM_PER_NODE
L22_MAX_STREAMS=100 L22_SCAN_MEM=16G L22_SCAN_TIME=04:00:00 \
    bash N4_volume_benchmark/submit_volume_beta_scan_ubelix.sh
```

The cancellation removes the old dependent comparison if it remains pending;
it may already have been canceled automatically. Existing failed-run records
are preserved, and the new submission uses a fresh results directory.

The submit helper prints a `sacct` command with the actual three job IDs.
Weight overlays are generated before the bootstrap in new scan jobs. To add
them to an existing scan without rerunning the ensemble analysis, use:

```bash
module load Python SciPy-bundle matplotlib
result_dir="$PWD/N4_L38_res/volume_scan.ACTUAL_SUFFIX"
python N4_volume_benchmark/plot_beta_weights.py --analysis "$result_dir/L22"
python N4_volume_benchmark/plot_beta_weights.py --analysis "$result_dir/L38"
```

Each command reads just the first selected full stream from `inputs.json`
(or `selected_runs.txt` if the ensemble bootstrap has not finished). It follows
continuation history when present. A specific run can also be plotted with
`--run /absolute/run/path --output /absolute/repository/output/path`.

For a completed scan, plots can be regenerated without repeating bootstraps:

```bash
module load Python SciPy-bundle matplotlib
result_dir="$PWD/N4_L38_res/volume_scan.ACTUAL_SUFFIX"
python N4_volume_benchmark/plot_volume_betas.py \
    --l22 "$result_dir/L22/beta_scan.csv" --l38 "$result_dir/L38/beta_scan.csv" \
    --output "$result_dir" \
    --mcmc-l38 /scratch/network/users/lb25v444/out_data/mcmc_38_N4_beta1p0_3x100k/job_22121710 \
    --mcmc-l22-search /scratch/network/users/lb25v444/out_data/mcmc_22_N4_beta0p7_3x1M
```

Run memory-intensive analysis under Slurm. The last command is for plot
regeneration; it also loads the MCMC data if supplied. Use an allocation with
adequate memory, or omit MCMC arguments to regenerate an NS-only plot.
