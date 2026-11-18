# N=4: L22/L38 volume comparison over beta

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
| 22 | 0.7 | 1,500 | 800 | 50,000 updates |
| 38 | 0.7 | 8,664 | 24 | 35,000 updates |

L22 uses exactly the 800 run directories listed in
`sh_files/analyze_N4_L22_ubelix.sh`. L38 uses four chains from each job
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
- `L22/inputs.json`, `L38/inputs.json`: exact inputs, settings, depth, bootstrap seed.
- `volume_comparison.csv`: both volumes and available MCMC references, with
  errors uniformly named `*_se` (bootstrap for NS; blocked jackknife for MCMC).
- `volume_shifts.csv`: L38 minus L22 for each beta and common observable,
  with independent-volume statistical errors added in quadrature.
- `ns_mcmc_comparison.csv`: NS minus direct MCMC at matching volume/beta,
  including combined statistical errors; written when references are available.
- `volume_dependence.png` and `.pdf`: action density, xi/L, topological
  susceptibility, G0, Gk, xi-squared. NS is **crimson**, MCMC **royalblue**;
  circles/solid lines identify L22, triangles/dashed lines L38.
- `coverage_diagnostics.png`: edge mass, stream-weight ESS, quadrature ESS.
- `mcmc_L22_binning.csv`, `mcmc_L38_binning.csv` when raw references exist.
- `jobs.tsv`, `settings.txt`, `comparison_settings.json`, `mcmc_status.txt`, job logs.

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

Defaults are 200 stream bootstraps, L22 64 GB / 24 hours, L38 8 GB / 4 hours,
comparison 16 GB / 2 hours. These are resource requests, not timing measurements.
The large L22 analysis reads 800 full streams and is the expensive stage.
Override `N_BOOTSTRAP`, `BOOTSTRAP_SEED`, `L22_SCAN_TIME`, `L38_SCAN_TIME` as needed.
`VOLUME_DATA_ROOT` changes the scratch base for all input families.

The submit helper prints a `sacct` command with the actual three job IDs.
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
