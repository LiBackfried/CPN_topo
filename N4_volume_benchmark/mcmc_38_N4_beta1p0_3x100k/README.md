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
