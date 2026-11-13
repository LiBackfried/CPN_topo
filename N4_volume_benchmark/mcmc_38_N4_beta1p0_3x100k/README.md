# Direct CP³ MCMC at L=38 and β=1.0

Run three independent fresh `cpn_N4` chains with `theta=0`. Each chain
runs 1,000,000 MC steps and measures every 10 steps, for 100,000 raw
measurements per chain. Each step uses four over-relaxation sweeps and one
over-heat-bath sweep. Topology is measured at cooling steps 0, 5, …, 50,
matching the L=38 nested-sampling run. Configurations and RNG state are
saved every 1,000 steps and at normal completion.

## Build and submit

From the `CPN_topo` repository root on UBELIX:

```bash
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
sbatch N4_volume_benchmark/mcmc_38_N4_beta1p0_3x100k/run_ubelix.sh
```

The build helper uses a private source copy and publishes `cpn_N4` in the
repository root. The launcher requests three tasks, one CPU and 512 MB per
task on `epyc2` under `gratis/job_gratis`, with a three-hour wall-time
limit. It snapshots the executable and inputs into the job directory.

## Check the output

Replace `JOB_ID` with the ID returned by `sbatch`:

```bash
job_id=JOB_ID
sacct -j "$job_id" --format=JobID,State,AllocCPUS,Elapsed,ExitCode
root="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_38_N4_beta1p0_3x100k/job_${job_id}"
ls "$root/completed"
cat "$root"/run_*/timing.txt
```

The launcher marks the job complete once each chain writes 100,000
`dati.dat` rows and 1,100,000 `topo.dat` rows, excluding headers. The
100,000 measurements per chain are an initial comparison sample. Before
estimating errors, check equilibration and autocorrelation of action and
cooled topological charge in each chain. Compare the direct action
histogram and the estimates of mean action density, `xi_L_squared`, and
`chi_topological` with the β=1.0 row at 35,000 cumulative updates in
`L38_depth_22120845.csv`. Use cooling step 50 for the topology comparison.

## Plot histories and binning errors

From the repository root, use the job directory set above:

```bash
module load Python SciPy-bundle matplotlib
python utils/plot_mcmc.py "$root"
```

Inspect `mcmc_analysis/histories.png` in the job directory to choose a
burn-in cut. Rerun with `--burn-in MC_STEPS` to exclude observations at or
before that stored MC step from the histogram and binning analysis. The
history plots still show the full run and shade the excluded period.
Topology defaults to the last recorded cooling step, 50 for this run.

`binning.png` and `binning.csv` give estimates and standard errors for
each chain and for the pooled sample. Bins contain 1, 2, 4, … consecutive
measurements and never cross chain boundaries. The script drops incomplete
tail bins and requires at least 16 bins per chain at each size. The x-axis
uses MC steps. The errors for `chi_topological` and `xi_L_squared` come
from a delete-one-bin jackknife that recomputes each observable from the
remaining measurements. Choose the plateau by inspecting the plot and
check that the chains agree and visit multiple charge sectors. Compare
`action_histogram.png` with the reweighted nested-sampling distribution.
