UBELIX: 10 fresh chains with 15000 stochastic updates

This batch launches 10 independent CP^(20) nested-sampling chains on a 72x72
lattice. Each chain uses 50 live points, 15000 stochastic single-site/link
updates per nested-sampling update, and performs exactly 1500 nested-sampling
updates (`num_ns_meas=1501` includes the initial measurement).

The chains use distinct RNG seeds 36774 through 36783 and start from fresh hot
configurations (`start=1`, `rng_start=0`).

Submit from `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo` with:

```bash
sbatch run_ns_constraint_72_N21_10x1500_stoc15000_ubelix.sh
```

Output is written to:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x1500_stoc15000/job_<JOB_ID>/run_<0..9>/
```

The job requests 10 tasks with one CPU and 2 GB RAM per task, with a 9-hour
time limit. Each task runs one independent chain.
