# CP^3 nested-sampling production batch: L=22, beta=0.7

The initial batch launches ten independent fresh nested-sampling chains for
the CP^3 model (`N=4`) on a 22x22 lattice. A second launcher adds 40 more
independent chains, and a third launcher adds another 50.

## Parameters

- `N=4` (compile time)
- lattice size 22x22
- beta 0.7 and theta 0
- 50 live points
- 4 microcanonical sweeps per NS update
- 1,500 stochastic single-field/link updates per NS update
- normalization after every stochastic update
- 50,000 NS updates per chain (`num_ns_meas=50001`)
- 100 fresh chains in total with distinct seeds 70421 through 70520
  - initial batch: runs 0 through 9, seeds 70421 through 70430
  - second batch: runs 10 through 49, seeds 70431 through 70470
  - third batch: runs 50 through 99, seeds 70471 through 70520

For a 22x22 lattice, three update types give `3 * 22^2 = 1452`; 1,500
stochastic updates is the rounded working value.

## UBELIX resources

All jobs use single-threaded tasks, one per chain, on `epyc2` with the
`job_gratis` QoS. They request 512 MB per task and a two-hour wall-time limit.
The three launchers request 10, 40, and 50 tasks, respectively. Together, the
100 chains yield 5,000,000 NS updates.

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

Submit the third batch of 50 with:

```bash
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_50_more_ubelix.sh
```

The build helper creates `cpn_ns_N4`, verifies its compiled value, and restores
the existing `include/macro.h` and `cpn_ns`. The job performs another N=4 check
and each job validates its configurations and seed uniqueness before starting.

Output is written below:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/job_<JOB_ID>/run_<RUN_ID>/
```

The three jobs use run IDs 0 through 9, 10 through 49, and 50 through 99. The
job-specific parent directories keep all outputs separate.

