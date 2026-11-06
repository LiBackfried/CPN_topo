# Regular CP³ Monte Carlo on UBELIX

This batch runs three fresh, independent `cpn` chains at `N=4`, on a
`22 × 22` lattice at `beta=0.7` and `theta=0`. The seeds are `4072201`,
`4072202`, and `4072203`.

Each chain runs 10,000,000 MC steps and records a measurement every 10 steps,
for 1,000,000 measurements per chain before any burn-in cut. Each step uses
four over-relaxation sweeps and one over-heat-bath sweep. The topology output
contains 11 rows per measurement, at cooling steps 0, 5, …, 50. The
configuration and RNG are checkpointed every 1,000 MC steps and at normal
completion.

## Build and submit

From `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo` on UBELIX:

```bash
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
sbatch N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/run_ubelix.sh
```

The build helper uses Autotools and creates `cpn_N4` from a private copy of
the source. The batch requests three tasks with one CPU and 512 MB per task on
`epyc2` using `gratis` and `job_gratis`. The four-hour limit allows headroom
over the roughly two-hour extrapolation from the local benchmark.

Use `sacct -j <JOB_ID> --format=JobID,State,AllocCPUS,Elapsed,ExitCode` to
verify that the allocation received three CPUs and that the job completed.

## Output

```text
/scratch/network/users/lb25v444/out_data/mcmc_22_N4_beta0p7_3x1M/job_<JOB_ID>/run_<0..2>/
```

Each chain directory contains its input, `dati.dat`, `topo.dat`, checkpoint
files, and run logs. At completion, `dati.dat` has 1,000,000 measurement rows
and `topo.dat` has 11,000,000 rows, excluding headers. Periodic field
checkpoints rotate between two backups. Slurm's batch log is in the checkout
as `slurm-<JOB_ID>.out`.
