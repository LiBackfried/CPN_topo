UBELIX: 10 fresh chains with 15500 stochastic updates

This batch launches 10 independent fresh CP^(20) nested-sampling chains on a
72x72 lattice. Each chain uses 50 live points, 15500 stochastic updates per
nested-sampling update, and performs exactly 1500 nested-sampling updates
(`num_ns_meas=1501` includes the initial measurement).

Submit from `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo` with:

```bash
sbatch run_ns_constraint_72_N21_10x1500_stoc15500_ubelix.sh
```

Fresh output is written below:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x1500_stoc15500/job_<JOB_ID>/run_<0..9>/
```

The job requests 10 tasks, one CPU and 2 GB RAM per task, with a 10-hour limit.
The previous 15000-update runs and their checkpoints are not modified.
