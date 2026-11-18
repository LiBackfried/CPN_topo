# Direct CP³ reference, L=66, beta=0.9

User-reported UBELIX simulation job: **22587511** (2026-11-18).
Completion and current Slurm state have not been checked remotely.

Three fresh, independently seeded N=4 chains, theta=0. Each has 1,000,000
MC steps, measurements every 10 steps (100,000 raw measurements), four
microcanonical sweeps, normalization every step, and 50 cooling steps
measured every five. Checkpoints are saved every 1,000 steps and at completion.
These match the L38 reference settings except L, beta and seeds; L22 uses
ten times as many steps. The 300,000 measurements across the three chains
are an initial reference, below the attached table's 3.1 million statistics.

From the repository root on UBELIX:

```bash
bash N4_L22_runs/mcmc_22_N4_beta0p7_3x1M/build_cpn_N4_ubelix.sh
sbatch N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh
```

The job requests three CPUs, 512 MB per CPU and four hours. Data are saved
under `${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_66_N4_beta0p9_3x100k/job_<ID>/run_<0..2>/`.
The launcher snapshots inputs/executable, refuses existing output directories,
checks N=4 and distinct positive seeds, and checks 100,000 data rows and
1,100,000 topology rows per chain before writing `completed`.

All analysis should be placed in repository `N4_L66_res/`. For example:

```bash
root="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/mcmc_66_N4_beta0p9_3x100k/job_<ID>"
module load Python SciPy-bundle matplotlib
python utils/plot_mcmc.py "$root" --output N4_L66_res/mcmc_job_<ID>/full
python utils/plot_mcmc.py "$root" --burn-in 20000 --output N4_L66_res/mcmc_job_<ID>/burn20000
```

The 20,000-step cut is inherited from L38 for the first diagnostic only.
Choose equilibration cut and error-bin plateau from these L66 histories,
including Q-sector transitions and agreement of all three chains. The target
is xi_L=5.398(22), or xi_L_squared=29.1384 with a propagated error of 0.2375.
