UPDATE: The second batch now also resumes. See ../ns_constraint_72_N21_10x5000_stoc5000_fresh2/README.md for the current submission command (defaults to original job 15985454). Its time limit is now 09:30:00. The fresh-start instructions below describe the previous setup.

UBELIX: continuation and 10 additional fresh chains

Submit from /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo on UBELIX after
copying the updated scripts and both configuration directories there.
The checkpoint data stays on UBELIX; no local data copy is required.

Continue the original 10 chains:
```bash
sbatch run_ns_constraint_72_N21_10x5000_stoc5000_ubelix.sh
```
The existing run_0 through run_9 configs now use start=2 and rng_start=1.
The job works directly in:
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000/job_15484566/run_<0..9>/
It checks all 50 live configuration files, live_energy.dat and rng_state.dat
on the cluster before launching. Submit only after the original job has stopped
at a consistent checkpoint, and do not run two continuations simultaneously.
Measurements and stdout/stderr are appended. The original input.conf is retained;
the resume input and previous log.dat are saved with the new job ID.
Live configurations, live energies and RNG state are updated in place.

Start 10 additional chains:
```bash
sbatch run_ns_constraint_72_N21_10x5000_stoc5000_fresh2_ubelix.sh
```
Configs are in config_files/ns_constraint_72_N21_10x5000_stoc5000_fresh2/.
They use start=1, rng_start=0 and distinct seeds 26774 through 26783
(the original seeds were 16774 through 16783).
Fresh output goes to:
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000_fresh2/job_<JOB_ID>/run_<0..9>/

Both batches retain 50 live points, 5000 stochastic updates per NS step,
and num_ns_meas=5001: one initial measurement plus 5000 update steps per
invocation. Continuation therefore adds 5000 steps, giving 10000 updates
if the original chains finished all 5000. The existing executable records
the checkpoint measurement again on restart and restarts acceptance iteration
labels at 1; account for this when joining/analyzing segments.
Other physical and sampling parameters are unchanged (72x72, N=21, beta=0.6).
Both jobs request 10 tasks, 1 CPU/task, 16 GB/CPU and 9 hours, retaining the
current UBELIX account, partition and QoS. Runtime has not been benchmarked.
Slurm launcher logs remain in the project directory.
