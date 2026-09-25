Third UBELIX batch: 10 fresh chains

Copy this configuration directory and the job script to the UBELIX project,
then submit from /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo:

```bash
sbatch run_ns_constraint_72_N21_10x5000_stoc5000_fresh3_ubelix.sh
```

Each chain starts fresh (start=1, rng_start=0), using seeds 36774 through 36783.
There are 50 live points and 5000 nested-sampling update steps per chain.
num_ns_meas=5001 includes the initial measurement plus those 5000 updates.
Other parameters match batch two, including 72x72, N=21, beta=0.6 and
5000 stochastic single-site/link updates per nested-sampling step.

The job requests 10 tasks, one CPU per task, 16 GB per CPU and 09:00:00,
with the same UBELIX account, partition, QoS and module as batch two.
The executable must already be compiled for N=21. Runtime is not benchmarked.

All simulation output and copied inputs go to:
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000_fresh3/job_<JOB_ID>/run_<0..9>/

Slurm launcher logs remain in the project directory. Existing output directories
are rejected to avoid overwriting data. This script starts fresh; continuation
requires resume configurations and the original output-folder job ID.
