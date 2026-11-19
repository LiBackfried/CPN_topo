# L90 screening campaign

On 2026-11-19 the user reported successful completion (`ExitCode=0:0`) of:

| Job | Role | CPUs | Reported elapsed |
| --- | --- | --- | --- |
| 22635137 | Three-chain direct MCMC, N=4, beta=0.95, 1M MC steps/chain | 3 | 04:33:29 |
| 22635195 | Four NS streams, N=4, source beta=0.7, 48,600 proposals/update, planned 80k updates/stream | 4 | 01:58:04 |

The user subsequently reported continuation job **22779059**, adding 60k
updates to job 22635195 for an expected cumulative 140k. Completion of that
continuation and submission of its dependent analysis have not been confirmed.

These are user-reported Slurm results; raw files, completion markers and remote
Slurm state have not been inspected locally. The analysis launcher checks
completion markers, lattice, task counts and source/target settings on UBELIX.
The NS scanner additionally checks segment lengths, measurement alignment,
N=4 logs and independent seeds. Four streams are a screening ensemble.

## Analyze the 80k run and the MCMC reference

Sync the new launcher to UBELIX, then submit from the repository root:

```bash
sbatch N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 22635137
```

The job requests one CPU, 16 GB and four hours. It scans NS prefixes at
20k, 40k, 60k and the deepest shared depth (expected 80k), reweighting to
beta=0.9, 0.95 and 1.0 with 200 paired whole-stream bootstrap draws.
It also writes MCMC histories, action histograms and binned jackknife
estimates with no burn-in and with a provisional 20,000-step cut.

Results and input records go to a new repository directory
`N4_L90_res/screen_ns22635195_mc22635137_analysis_<ANALYSIS_JOB_ID>/`.
The `completed` marker refers to successful analysis, not demonstrated
equilibration, sufficient depth or agreement with MCMC.

At beta=0.95 inspect `last_tenth_target_mass`, `q99_points_per_stream`,
stream concentration and paired observable shifts. The L66-based estimate
put q99 near 107k for L90, so an 80k prefix may still be truncated.
A small observed edge mass is only a screen; inspect the missing-weight
bound and compare deeper prefixes. Choose MCMC burn-in and bin size from
histories, chain agreement, topology and the bin-error plateau.

## Continue to 140k while analyzing the existing data

The next segment adds 60,000 updates to the planned 80,000:

```bash
base="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}"
unset NS_STOC NS_INIT_SWEEPS NS_INIT_SPACING NS_SEED_BASE NS_EXECUTABLE
sbatch --ntasks=4 --cpus-per-task=1 --time=04:00:00 \
    N4_volume_benchmark/run_ubelix.sh 90 60000 \
    "$base/ns_N4_beta0p7_volume_benchmark/L90/job_22635195"
```

The continuation inherits the executable, seeds/RNG state and proposal count.
It copies validated parent checkpoints into a fresh job directory, so the
original measurements remain available for concurrent analysis. Keep the
ancestor directories. The four descendant streams remain the same four
independent streams; they do not increase the independent-stream count.

At the measured 6L² pilot rate this segment projects to about 1.55 hours
per stream; the four-hour request provides headroom for depth and I/O.
The continuation writes `num_ns_meas=60001` for the segment.

After successful completion, analyze only the new leaf:

```bash
sbatch --dependency=afterok:22779059 N4_volume_benchmark/analyze_L90_ubelix.sh 22779059 22635137 \
    40000 80000 100000 120000
```

The deepest shared prefix (expected 140k) is added automatically. Compare
100k/120k/140k results at beta=0.95 before selecting depth or expanding
to twelve independent streams. Formal correlator-bin comparison can follow
once the NS common cutoff covers the direct MCMC action range.

## Reported timing pilots

L90 timing campaign:
`/scratch/network/users/lb25v444/out_data/cpn_N4_L90_L120_timing.vcKkCf/`.
Jobs 22630148–22630153 were reported completed. The four-pair 6L² median
was 0.092958333 s/NS update; target MCMC was 0.018226111 s/MC step.
Two 3L² pairs were excluded for CPU-model or seed mismatch, leaving a
two-pair median of 0.083100000 s/update.

The user also reported completed L120 pilot jobs 22630183, 22630184,
22630185, 22630187, 22630188 and 22630189 in campaign
`/scratch/network/users/lb25v444/out_data/cpn_N4_L90_L120_timing.r4itZM/`.
Their four-pair medians were 0.142633333 s/update at 3L²,
0.172797222 s/update at 6L² and 0.032889166 s/MC step at beta=1.0.
These reports establish timing; no full-length L120 production job was
reported in this list.
