UBELIX batch 3: continuation

Submit from /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo after copying
this configuration directory and the updated job script to UBELIX:

    sbatch run_ns_constraint_72_N21_10x5000_stoc5000_fresh3_ubelix.sh

The default original job ID is 16235818. An optional numeric argument overrides it.
Existing remote checkpoints and output are used in place at:
/scratch/network/users/lb25v444/out_data/ns_constraint_72_N21_10x5000_stoc5000_fresh3/job_16235818/run_<0..9>/

All 10 configs use start=2 and rng_start=1. Each continuation performs 4500
additional nested-sampling updates (num_ns_meas=4501 includes the initial
measurement). The 50 live points, seeds, physical parameters and 5000 stochastic
single-site/link updates per NS step are unchanged. The time limit is 09:00:00.

The script checks all 50 live files, live_energy.dat and rng_state.dat before
starting. It appends measurements and stdout/stderr, preserves input.conf,
and saves the resume input and previous log.dat with the new Slurm job ID.
Live configurations, energies and RNG state are updated in place.
Submit only after the previous run has stopped at a consistent checkpoint,
and do not run simultaneous continuations of the same data.
The executable repeats the initial checkpoint measurement and resets acceptance
iteration labels to 1 on restart; account for this in analysis.