# L120 screening campaign

The requested expansion to **24 NS streams at 300k updates each** is
user-reported submitted on 2026-11-24. Starts **23350702/23350704/23350706**
each add four fresh streams at 150k; dependent leaves
**23350703/23350705/23350707** take the same streams to 300k. Analysis
**23350708** waits for all three leaves, combines existing12 plus new12
and reuses MCMC **22780263**. Completion has not been verified. See
[the 24-stream setup](ADD_12_TO24_STREAMS_300K.md) and
[the submission record](reported_add12_to24_jobs_20261124.tsv).

On 2026-11-21 the user reported submission of robustness analysis
**22974798**, covering the bin/block grid, three four-stream groups and
twelve leave-one-out subsets of the completed 300k ensemble. Records/logs:
`/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/robustness_submit.Eh36vA`.
The results were copied on 2026-11-23 to `robustness_steps12_22974798/`,
with analysis and record completion markers. The pooled bin comparison
stays within its joint 95% thresholds; four-stream group residuals still
leave sampling validation open. See
[the robustness review](../N4_volume_benchmark/ROBUSTNESS_REVIEW_20261123.md),
[the submission record](reported_robustness_jobs_20261121.tsv) and
[the analysis guide](../N4_volume_benchmark/ROBUSTNESS_STEPS_1_2.md).

This is an N=4, theta=0 campaign independent of the L90 jobs. NS uses
source beta=0.7 and direct MCMC uses target beta=1.0. On 2026-11-19 the
user reported submission of the first screening campaign described below.

The latest completed analysis, copied on 2026-11-21, is **22904265** at
`combined300_ns22885157_analysis_22904265/`: **twelve independent streams,
300k updates each**, combining existing leaf 22885157 with new leaves
22904262 and 22904264. The earlier four-stream analyses **22780264**,
**22860160** and **22885274** remain available. All have `completed`
markers. The ensemble uses 86,400 proposals/update and MCMC **22780263**
remains the reference; its copied diagnostics are unchanged.
The records are in [reported_jobs_20261120.tsv](reported_jobs_20261120.tsv).

The updated [results review](RESULTS_REVIEW.md) finds that **300k passes
the observed depth screens through beta=1.0**. At that target, 270k and
300k estimates agree to saved numerical precision; final-tenth mass is
0.1810% at 270k and 2.99e-21 at 300k in the twelve-stream analysis.
All integrated beta=1.0 NS/MCMC observables agree within 1.3 combined
SE. NS gives xi_L=9.450 +/- 0.635 and MCMC gives 9.938 +/- 0.148.

The 32-bin comparison has one conditional G0 bin at 3.32 reported SE;
no Gk bin exceeds two. Rebinning, joint error assessment and mixing
checks remain priorities. The depth diagnostics give no reason for a
further production extension. Remote Slurm state and raw simulation/
checkpoint files have not been inspected in this local review.

On 2026-11-20 the user reported submission of the eight additional streams:

| Batch | First 150k job | Leaf at 300k | Seed labels for run_0 through run_3 |
| --- | --- | --- | --- |
| Four new streams, batch 1 | 22904261 | 22904262 | 335358449–335358452 |
| Four new streams, batch 2 | 22904263 | 22904264 | 691294503–691294506 |

Analysis **22904265** was queued with `afterok:22904262:22904264`, combines the
eight new streams with existing NS **22885157**, and reuses MCMC
**22780263**. The reported campaign directory is:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/add8_300k.stUQg8
```

See [reported_add8_jobs_20261120.tsv](reported_add8_jobs_20261120.tsv)
and [ADD_8_STREAMS_300K.md](ADD_8_STREAMS_300K.md) for dependencies,
seed ranges and output paths. The completed analysis and campaign records
are now copied locally, including twelve distinct seed labels. The
submission table is historical; current remote Slurm states/resources
have not been queried. Repeating the driver would submit another eight
streams.

## Reported submissions (2026-11-19)

| Job ID | Role | Reported status | Dependency |
| --- | --- | --- | --- |
| 22780262 | Four NS streams, 120k updates each, 86,400 proposals/update | Submitted | None |
| 22780263 | Three beta=1.0 MCMC chains, 1M MC steps each | Submitted | None |
| 22780264 | NS depth scan and MCMC diagnostics | Queued | `afterok:22780262:22780263` |

The user reported campaign records and Slurm logs at:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/campaign.op3KHS
```

The submitted IDs, dependency and expected output directories are also in
[reported_jobs_20261119.tsv](reported_jobs_20261119.tsv). These entries
transcribe the user's submission output. The completed local analysis
marker and CSVs have now been checked; current Slurm state, allocated
resources and raw remote run files have not been inspected. This campaign
has already produced its initial analysis; the start command below
creates another fresh campaign if repeated.

The expected analysis result directory is:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/screen_ns22780262_mc22780263_analysis_22780264
```

To inspect these jobs on UBELIX:

```bash
sacct -j 22780262,22780263,22780264 \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

## Start NS and MCMC, then analyze both

Sync the new launchers/configs to UBELIX and run from the CPN_topo root:

```bash
bash N4_volume_benchmark/fresh_L120_screen_ubelix.sh
```

The driver reuses the existing N=4 executables and submits:

| Job | Settings | CPUs | Wall-time request |
| --- | --- | --- | --- |
| NS screening | Four independent streams, 50 live points, 86,400 proposals/update, 120k NS updates/stream | 4 | 12 h |
| Direct MCMC | Three independent beta=1.0 chains, 1M MC steps/chain | 3 | 16 h |
| Analysis | Paired whole-stream depth scan and MCMC diagnostics | 1 | 4 h |

Both simulation jobs can run alongside L90 as Slurm resources allow. The
analysis has an `afterok` dependency on both L120 simulations and no
dependency on L90. It verifies their `completed` markers and settings
before running. The driver clears inherited `SBATCH_*` options, sets NS
initialization to 20 burn-in steps and spacing eight, and derives distinct
NS seeds from the new job ID. MCMC seeds are 4112001–4112003.

NS retains four microcanonical sweeps, normalization every step, 50 cooling
steps measured every five and `save_dead=0`. `num_ns_meas=120001` includes
the initial measurement. MCMC uses the same microcanonical/normalization/
cooling settings, measures every ten MC steps and saves configurations
every 1,000. Each chain has a separate working directory.

The driver writes `jobs.tsv`, Slurm logs and an analysis retry command to
a fresh repository `N4_L120_res/campaign.XXXXXX/` directory. If submission
fails partway through, inspect that manifest before retrying: already
submitted jobs are left in place. Repeating the driver submits a new
campaign; the fixed MCMC seeds repeat the same three streams.

Verify allocations after submission:

```bash
sacct -j <NS_ID>,<MCMC_ID>,<ANALYSIS_ID> \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

Expect four NS CPUs, three MCMC CPUs and one analysis CPU. The scripts
do not require a rebuild when the existing executables are N=4 and the
simulation sources have not changed.

## Data and analysis outputs

Under `${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}`:

- NS: `ns_N4_beta0p7_volume_benchmark/L120/job_<NS_ID>/run_<0..3>/`.
- MCMC: `mcmc_120_N4_beta1p0_3x100k/job_<MCMC_ID>/run_<0..2>/`.

Analysis goes to repository
`N4_L120_res/screen_ns<NS_ID>_mc<MCMC_ID>_analysis_<ANALYSIS_ID>/`.
It contains `depth.csv`, input records, and `mcmc_full/` and
`mcmc_burn20000/` histories, action histograms and binning summaries.
The 20,000-step burn-in cut is provisional and should be checked against
histories, agreement across chains, Q-sector transitions and a bin-error plateau.

The depth scan uses 30k, 60k, 90k and the deepest shared prefix (expected
120k), targets beta=0.9, 0.95 and 1.0, and 200 paired whole-stream bootstrap
draws. Four streams provide screening uncertainty. The initial 120k stage
is not expected to establish beta=1.0 coverage: scaling the L66 q99 gives
about 249k points per stream. The planned cumulative stages remain
120k -> 240k -> 370k, to be revised using actual coverage and timing.
Small observed edge mass alone does not establish complete target coverage
or unbiased constrained sampling.

After the initial analysis, the existing continuation launcher can add
another 120k updates to the completed NS parent:

```bash
base="${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}"
unset NS_STOC NS_INIT_SWEEPS NS_INIT_SPACING NS_SEED_BASE NS_EXECUTABLE
sbatch --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
    N4_volume_benchmark/run_ubelix.sh 120 120000 \
    "$base/ns_N4_beta0p7_volume_benchmark/L120/job_22780262"
```

It copies validated checkpoints and inherits the executable, proposal count,
settings and RNG states. Keep the ancestor directories. The descendants
remain the same four independent streams. After completion, analyze only
the new leaf and reuse the completed MCMC reference:

```bash
sbatch N4_volume_benchmark/analyze_L120_ubelix.sh \
    22860149 22780263 60000 120000 180000 210000
```

The deepest shared depth (expected 240k) is added automatically. A formal
NS/MCMC comparison should follow adequate target coverage and MCMC checks.

## Timing evidence

The user reported completed L120 timing jobs 22630183, 22630184, 22630185,
22630187, 22630188 and 22630189 in scratch campaign
`cpn_N4_L90_L120_timing.r4itZM/`. Four-pair medians on EPYC 7742 were
0.172797222 s/NS update at 6L² and 0.032889166 s/MC step at beta=1.0.
These project to 5.76 h for 120k NS updates per stream and 9.14 h for a
million-step MC chain, excluding initialization and assuming comparable
rates persist. CPU consumption sums over concurrent streams. Recheck
timing near deeper cutoffs before budgeting later stages.
