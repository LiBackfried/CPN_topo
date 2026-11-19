# L120 screening campaign

This prepares an N=4, theta=0 campaign independent of the L90 jobs. NS
uses source beta=0.7 and direct MCMC uses target beta=1.0. The previously
reported L120 jobs are timing pilots; no full-length L120 production job
has been reported or submitted by the assistant.

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
    "$base/ns_N4_beta0p7_volume_benchmark/L120/job_<NS_PARENT_ID>"
```

It copies validated checkpoints and inherits the executable, proposal count,
settings and RNG states. Keep the ancestor directories. The descendants
remain the same four independent streams. After completion, analyze only
the new leaf and reuse the completed MCMC reference:

```bash
sbatch N4_volume_benchmark/analyze_L120_ubelix.sh \
    <NS_LEAF_ID> <MCMC_ID> 60000 120000 180000 210000
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
