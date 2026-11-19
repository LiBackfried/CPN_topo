# L90: extend four streams and add eight, all to 210k

This prepares twelve independent N=4, L90, theta=0 NS streams at source
beta=0.7, with 50 live points and 48,600 stochastic proposals per update.
It continues the four existing streams from 140k to 210k and adds eight
fresh streams of 210k updates each. The same completed beta=0.95 MCMC
reference, job 22635137, is reused. No new MCMC job is submitted.

## Submit on UBELIX

Sync the new driver and analysis launcher to the UBELIX checkout, then
run from the repository root:

```bash
bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh
```

The default parent is **22779059** (80k original updates plus the 60k
continuation). The optional arguments select another completed 140k
parent and MCMC reference:

```bash
bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh 22779059 22635137
```

The driver submits three simulation jobs and a dependent analysis:

| Role | Independent streams | Updates added per stream | Total per stream | CPUs | Wall-time request |
| --- | ---: | ---: | ---: | ---: | ---: |
| Continuation of 22779059 | Existing 4 | 70,000 | 210,000 | 4 | 4 h |
| Fresh batch 1 | New 4 | 210,000 | 210,000 | 4 | 8 h |
| Fresh batch 2 | New 4 | 210,000 | 210,000 | 4 | 8 h |
| Combined analysis | All 12 | — | Common prefixes through 210,000 | 1 | 12 h |

Simulation tasks use one CPU and 512 MB per stream. Analysis requests
16 GB. The three simulation jobs may run concurrently as Slurm resources
allow. The analysis has an `afterok` dependency on all three; the MCMC
reference is required to be completed before submission.

At the measured early pilot rate of 0.092958333 s/update, the continuation
projects to 1.81 hours per stream and a fresh run to 5.42 hours per stream,
excluding initialization. Additional aggregate simulation CPU consumption
projects to about 50.6 CPU-hours. These are projections, not measured
deep-run timings. Requests provide headroom; assess rates again from the
new jobs' timing reports.

## Preflight and reproducibility

Before any submission the driver:

- Requires the parent job's `completed` marker, L90 and four tasks.
- Checks all 50 live configurations, `live_energy.dat` and `rng_state.dat`
  for each of the four leaf streams.
- Follows each `parent_run` history, rejects cycles/incomplete ancestors,
  checks fresh/resume flags and seed consistency, and requires exactly
  140,000 cumulative updates in every stream.
- Checks source beta, theta, live points, proposals, initialization,
  microcanonical sweeps, normalization and cooling settings, and compares
  every other ensemble parameter against the transformed fresh template.
- Verifies the parent's saved executable reports N=4. Fresh jobs use that
  same executable, rather than requiring a new checkout build.
- Verifies the existing three-chain L90 beta=0.95 MCMC reference.

The continuation inherits its original seeds/RNG states and executable.
Inherited NS parameter overrides are removed from its submission
environment. Fresh jobs explicitly use `start=1`, `rng_start=0`, 20
initial MC burn-in steps, live-point spacing eight, four microcanonical
sweeps, normalization every step and 50 cooling sweeps measured every five.
The driver clears inherited `SBATCH_*` overrides.

Eight fresh positive RNG seeds are allocated before submission using two
four-seed blocks, checked against each other, the four inherited NS seeds
and the MCMC seeds, and saved in `planned_seeds.tsv`. They do not depend
on an unrecorded initialization state. Seeds are in the executable's ran2
range. The twelve rows in that file refer to twelve NS streams; a
continuation is part of an existing stream, not an additional one.

The continuation segment gets `num_ns_meas=70001`, and each fresh stream
gets `num_ns_meas=210001`. The generic launcher copies the parent
checkpoints into a new job directory and snapshots the executable;
parent files are read-only inputs. Keep jobs 22635195 and 22779059 and
their existing relative parent layout for later analysis. Every stream
has its own working directory, and output reuse is rejected.

## Submission records and outputs

The driver creates repository `N4_L90_res/extend210k.XXXXXX/`, containing:

- `jobs.tsv`: submitted IDs, roles, expected directories and segment/total depths.
- `planned_seeds.tsv`: inherited and newly reserved NS seeds.
- `parent_directory.txt`, `parent_executable_sha256.txt`, `mcmc_job_id.txt`.
- Slurm logs, `analysis_job_id.txt` and `analyze_command.txt` for retrying analysis.

Raw simulation data remain under
`${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/ns_N4_beta0p7_volume_benchmark/L90/job_<ID>/run_<0..3>/`.
Set `NS_SCRATCH` if the existing campaign uses another scratch parent.

Inspect all four new allocations after submission:

```bash
sacct -j <CONTINUATION_ID>,<FRESH1_ID>,<FRESH2_ID>,<ANALYSIS_ID> \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

Expect four CPUs in each simulation allocation and one in analysis.
If submission fails partway through, successful jobs remain recorded and
are not cancelled. Inspect the manifest and jobs before retrying the
driver: repeating it branches the same four parent streams again and
submits another eight fresh ones. Use the saved analysis retry command
if only analysis submission failed. No automatic resubmission is performed.

## Combined analysis

Results go to repository
`N4_L90_res/combined210_ns<CONTINUATION_ID>_analysis_<ANALYSIS_ID>/`.
Only the three new leaf jobs are passed; their ancestors are followed
automatically and repeated continuation boundary measurements are dropped.
The effective merged live-point count is 12*50=600. Entire independent
streams are bootstrapped with replacement and remerged at every draw.

The analysis produces:

- `depth.csv`: 100k, 120k, 140k, 160k, 180k, 200k and 210k at beta=0.9,
  0.95 and 1.0, with 200 paired whole-stream bootstrap replicates.
- MCMC histories/histograms/binning with no cut and with a provisional
  20,000-MC-step cut.
- `action_bins32_beta0p95/`: a matched 32-bin correlator comparison at
  210k, beta=0.95, using MCMC blocks of 128 measurements and 200 NS
  bootstrap replicates.
- Input job records and a `completed` marker only after all tasks succeed.

To submit the same analysis separately from the repository root:

```bash
sbatch N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh \
    <CONTINUATION_ID> <FRESH1_ID> <FRESH2_ID> 22635137
```

The explicit 210k prefix prevents an analysis from silently accepting a
shorter shared dataset. Check coverage, paired shifts, stream concentration
and the beta=0.95 MCMC comparison. The depth and stream count are planned
settings, not a guarantee of target coverage or constrained mixing.
Changes to initialization or proposal counts belong in separate validation
ensembles; this campaign keeps the current settings for a common analysis.

## Local verification

```bash
bash N4_volume_benchmark/validate_L90_210k_launchers.sh
```

This uses mock Slurm, Python and simulation executables. It tests
checkpoint/history checks, all twelve seeds, generated update counts and
flags, parent immutability, dependencies, analysis routing and failure
records without submitting remote jobs or generating physics results.
