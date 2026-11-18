# Direct CP³ reference: L90, beta=0.95

Three independent fresh N=4, theta=0 chains with seeds 4109001–4109003.
Each runs 1,000,000 MC steps and measures every ten, producing 100,000 raw
measurements before burn-in (300,000 across all chains). The directory's
`3x100k` refers to measurements, not MC steps.

Settings match the L66 reference apart from volume, beta, seeds and wall-time:
four microcanonical sweeps, normalization every step, checkpoints every
1,000 steps, and 50 cooling steps measured every five. The initial request
is three single-threaded tasks, 512 MB per CPU and twelve hours on `epyc2`
with `gratis/job_gratis`. The rough six-hour per-chain projection is based
on L66 scaling; use the actual beta=0.95 timing pilot to adjust the request.

From the UBELIX repository root:

```bash
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
sbatch N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh
```

Submit with `sbatch`, including inside Open OnDemand. Verify three CPUs
with `sacct`/`scontrol` after submission. The launcher checks compiled N,
all input settings and distinct positive seeds, snapshots the executable
and configs, and refuses existing output directories. `completed` is written
only after all three chains have 100,000 data rows, 1,100,000 topology rows
and nonempty configuration/RNG checkpoints.

Raw data go to
`${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_90_N4_beta0p95_3x100k/job_<ID>/run_<0..2>/`.
Each chain has its own directory, timing report and CPU-model record.
Save analysis under repository `N4_L90_res/`, for example:

```bash
root="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_90_N4_beta0p95_3x100k/job_<ID>"
module load Python SciPy-bundle matplotlib
python utils/plot_mcmc.py "$root" --output N4_L90_res/mcmc_job_<ID>/full
python utils/plot_mcmc.py "$root" --burn-in 20000 --output N4_L90_res/mcmc_job_<ID>/burn20000
```

The 20,000-step cut is a first diagnostic inherited from L66. Choose the
final cut from action/Q histories, independent-chain agreement and a bin-error
plateau. Reassess the length if topology mixes slowly or errors do not plateau.
The user's transcribed table gives xi_L=7.314(33) for this volume and beta;
its statistics exceed this initial reference. A matching comparison needs
NS sourced at beta=0.7 and correctly reweighted to beta=0.95.

For the paired NS/MCMC timing campaign, see
[L90_L120_BENCHMARK.md](../L90_L120_BENCHMARK.md).
