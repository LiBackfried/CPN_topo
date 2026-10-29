# CP^3 nested-sampling production batch: L=22, beta=0.7

The initial batch launches ten independent fresh nested-sampling chains for
the CP^3 model (`N=4`) on a 22x22 lattice. A second launcher adds 40 more
independent chains, and a third launcher adds another 50 as two Slurm-array
elements of 25 chains each. A fourth launcher adds 100 more as four independent
Slurm-array jobs of 25 chains each, and a fifth launcher adds another 100 using
the same four-by-25 layout. A sixth launcher adds runs 300 through 399 with the
same layout again.

## Parameters

- `N=4` (compile time)
- lattice size 22x22
- beta 0.7 and theta 0
- 50 live points
- 4 microcanonical sweeps per NS update
- 1,500 stochastic single-field/link updates per NS update
- normalization after every stochastic update
- 50,000 NS updates per chain (`num_ns_meas=50001`)
- 400 fresh chains in total with distinct seeds 70421 through 70820
  - initial batch: runs 0 through 9, seeds 70421 through 70430
  - second batch: runs 10 through 49, seeds 70431 through 70470
  - third batch: runs 50 through 99, seeds 70471 through 70520
  - fourth batch: runs 100 through 199, seeds 70521 through 70620
  - fifth batch: runs 200 through 299, seeds 70621 through 70720
  - sixth batch: runs 300 through 399, seeds 70721 through 70820

For a 22x22 lattice, three update types give `3 * 22^2 = 1452`; 1,500
stochastic updates is the rounded working value.

## UBELIX resources

All jobs use single-threaded tasks, one per chain, on `epyc2` with the
`job_gratis` QoS. They request 512 MB per task and a two-hour wall-time limit.
The first two launchers request 10 and 40 tasks. The third uses a two-element
Slurm array with 25 tasks per element: array element 0 runs IDs 50 through 74,
and array element 1 runs IDs 75 through 99. The fourth uses four array elements
of 25 tasks for run IDs 100 through 199. The fifth repeats that four-by-25
layout for run IDs 200 through 299, and the sixth does the same for run IDs 300
through 399. Together, the 400 chains yield 20,000,000 NS updates.

## Build and submit

From `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo`:

```bash
bash N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_ubelix.sh
```

After the initial ten runs have finished, submit the additional 40 with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_40_more_ubelix.sh
```

Submit the third batch of 50 as two independent 25-stream allocations with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_50_more_ubelix.sh
```

Submit the fourth batch of 100 as four independent 25-stream allocations with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_100_more_ubelix.sh
```

Submit the fifth batch of 100 as four independent 25-stream allocations with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_100_more_200_299_ubelix.sh
```

Submit the sixth batch of 100 as four independent 25-stream allocations with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_100_more_300_399_ubelix.sh
```

The build helper creates `cpn_ns_N4`, verifies its compiled value, and restores
the existing `include/macro.h` and `cpn_ns`. The job performs another N=4 check
and each job validates its configurations and seed uniqueness before starting.

Output is written below:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/job_<JOB_ID>/run_<RUN_ID>/
```

The launchers use run IDs 0 through 9, 10 through 49, 50 through 99, 100
through 199, 200 through 299, and 300 through 399. Each array element has its
own Slurm job ID and therefore its own job-specific output directory.

