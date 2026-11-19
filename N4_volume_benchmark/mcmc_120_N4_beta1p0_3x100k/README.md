# Direct CP³ reference: L120, beta=1.0

Three independently seeded fresh N=4, theta=0 chains (4112001–4112003).
Each runs 1,000,000 MC steps, measures every ten and produces 100,000 raw
measurements before burn-in. `3x100k` denotes measurements. There are
four microcanonical sweeps, normalization every step, checkpoints every
1,000 steps and 50 cooling steps measured every five.

The job requests three single-threaded CPUs, 512 MB per CPU and sixteen
hours on `epyc2` with `gratis/job_gratis`. The user's completed timing
pilots project to about 9.14 hours per chain, excluding initialization.
The extra requested time provides headroom; actual rate and mixing at
beta=1.0 need checking from the production data.

From the repository root on UBELIX, with an existing N=4 `cpn_N4`:

```bash
sbatch N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh
```

The launcher checks N, every config field and distinct positive seeds;
snapshots the executable and configs; rejects output reuse; and requires
100,000 data rows, 1,100,000 topology rows and nonempty configuration/RNG
checkpoints for every chain before marking the job `completed`.

Raw data go to
`${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_120_N4_beta1p0_3x100k/job_<ID>/`.
Save analysis under `N4_L120_res/`. Choose the burn-in cut and error bin size
from histories, Q-sector coverage, chain agreement and a bin-error plateau.
The user's table gives xi_L=9.997(45) at this volume and beta; this initial
reference has fewer measurements than that table's statistics.

To start this reference together with four NS streams and dependent
analysis, use `bash N4_volume_benchmark/fresh_L120_screen_ubelix.sh`
instead of separately submitting the MCMC job. See
[N4_L120_res/README.md](../../N4_L120_res/README.md).
