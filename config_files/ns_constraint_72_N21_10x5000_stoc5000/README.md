UBELIX: 10 independent stochastic heatbath nested-sampling chains

From /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo on UBELIX, after
transferring the current source, job script, and this configuration directory:

```bash
bash script_build_code.sh
bash script_compile_code_ubelix.sh 21 cpn_ns
sbatch run_ns_constraint_72_N21_10x5000_stoc5000_ubelix.sh
```

Each chain uses 50 live points, 5000 nested-sampling update steps, and
5000 stochastic single-site/link updates per step. The other parameters match
the 72x72, N=21, beta=0.6 trial runs. Seeds are 16774 through 16783.
Fresh starts use start=1 and rng_start=0; dead configurations are not saved.
num_ns_meas=5001 includes the initial measurement followed by 5000 updates
(the current C loop runs from i=1 through i<num_ns_meas).

All simulation output, live configurations, RNG state, acceptance data, copied
input, stdout.log, and stderr.log are written beneath:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000/job_<JOB_ID>/run_<0..9>/
```

Slurm's launcher log remains slurm-<JOB_ID>.out in the project directory.
The job requests 10 tasks, one CPU per chain, and 24 GB per CPU (240 GB total).
It retains the account, partition, QoS, and 12-hour time limit from
run_mult_streams.sh. Completion within 12 hours has not been benchmarked.
Adjust the time request if needed under the cluster's allocation rules.
Each submission starts fresh in a new job directory; automatic requeue into
an existing directory is rejected to prevent mixing or overwriting output.
A continuation requires separate resume configurations.
