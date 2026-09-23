Second UBELIX batch: continuation

All run_0 through run_9 configurations use start=2 and rng_start=1.
Each invocation adds 5000 updates (num_ns_meas=5001), with 50 live points.
Seeds and other sampling parameters remain unchanged; the saved RNG state is loaded.
The job requests 9 hours 30 minutes and resumes in the existing remote directories.

After copying the configs and job script to UBELIX, submit:
```bash
sbatch run_ns_constraint_72_N21_10x5000_stoc5000_fresh2_ubelix.sh
```
The script defaults to original job 15985454, whose files are in:
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000_fresh2/job_15985454/
An optional job-ID argument overrides the default. Use the original output-folder ID even for subsequent continuations.

The script checks checkpoint files on UBELIX, appends measurement and stdout/stderr
output, preserves input.conf, and saves resume inputs and the previous log.dat
under names containing the new Slurm job ID. Live checkpoints are updated in place.
Run only after the previous job has stopped at a consistent checkpoint; do not
submit simultaneous continuations of the same data. Restart repeats the initial
checkpoint measurement and resets acceptance iteration labels to 1.
