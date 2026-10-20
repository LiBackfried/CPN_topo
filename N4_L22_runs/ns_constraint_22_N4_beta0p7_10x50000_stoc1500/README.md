# CP^3 nested-sampling production batch: L=22, beta=0.7

This batch launches ten independent fresh nested-sampling chains for the
CP^3 model (`N=4`) on a 22x22 lattice. It follows the recent N=21 UBELIX setup,
with the requested model parameters and run length changes.

## Parameters

- `N=4` (compile time)
- lattice size 22x22
- beta 0.7 and theta 0
- 50 live points
- 4 microcanonical sweeps per NS update
- 1,500 stochastic single-field/link updates per NS update
- normalization after every stochastic update
- 50,000 NS updates per chain (`num_ns_meas=50001`)
- ten fresh chains with distinct seeds 70421 through 70430

For a 22x22 lattice, three update types give `3 * 22^2 = 1452`; 1,500
stochastic updates is the rounded working value.

## UBELIX resources

The job launches ten single-threaded tasks, one per chain, on `epyc2` with the
`job_gratis` QoS. It requests 512 MB per task and a two-hour wall-time limit.
This is substantially below the old N=21 request while retaining generous
headroom for filesystem and node-performance variation. The ten chains yield
500,000 NS updates in total.

## Build and submit

From `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo`:

```bash
bash N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh
sbatch N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_ubelix.sh
```

The build helper creates `cpn_ns_N4`, verifies its compiled value, and restores
the existing `include/macro.h` and `cpn_ns`. The job performs another N=4 check
and validates all ten configurations and seed uniqueness before starting.

Output is written below:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/job_<JOB_ID>/run_<0..9>/
```

