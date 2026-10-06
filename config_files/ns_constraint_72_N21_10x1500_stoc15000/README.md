UBELIX: continue 10 chains with 15000 stochastic updates

This batch continues the 10 independent CP^(20) nested-sampling chains created
by Slurm job 17336277. Each chain uses 50 live points, 15000 stochastic
single-site/link updates per nested-sampling update, and performs exactly 2000
additional nested-sampling updates (`num_ns_meas=2001` includes the repeated
checkpoint measurement).

The configurations load the existing live points and RNG state (`start=2`,
`rng_start=1`). Do not run this continuation while another job is writing to
the same checkpoint directories.

Submit from `/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo` with:

```bash
sbatch run_ns_constraint_72_N21_10x1500_stoc15000_ubelix.sh
```

Job 17336277 is the default. To target a different initial job directory, pass
its numeric ID as the only argument to `sbatch`.

Output is written to:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x1500_stoc15000/job_17336277/run_<0..9>/
```

The job requests 10 tasks with one CPU and 2 GB RAM per task, with a 10-hour
time limit. Each task continues one independent chain. Existing measurement and
stdout/stderr files are appended; the resume input and previous log are retained
with the continuation job ID.
