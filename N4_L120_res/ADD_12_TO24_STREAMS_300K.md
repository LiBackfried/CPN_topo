# L120 expansion from twelve to twenty-four streams

Prepared locally on 2026-11-24 at the user's request. On the same date the
user reported the submissions below. Remote execution/completion has not
been independently verified.

Add **twelve fresh independent NS streams**, each with **300,000 updates**,
to the existing twelve. Keep N=4, L=120, source beta=0.7, theta=0, 50 live
points/stream and **86,400 proposals/update**. Initialization remains 20 MC
cycles followed by live-point spacing eight, with four microcanonical sweeps,
`num_norm=1` and cooling 50 measured every five. This increases the statistics
of the existing production ensemble; initialization/mixing validation remains
a separate study with separately identified settings.

## Reported submissions on 2026-11-24

| Job | Role | Cumulative updates/stream | Reported status | Dependency |
| --- | --- | ---: | --- | --- |
| 23350702 | Fresh batch1, four streams | 150,000 | Submitted | None |
| 23350703 | Batch1 continuation, same four | 300,000 | Queued | `afterok:23350702` |
| 23350704 | Fresh batch2, four streams | 150,000 | Submitted | None |
| 23350705 | Batch2 continuation, same four | 300,000 | Queued | `afterok:23350704` |
| 23350706 | Fresh batch3, four streams | 150,000 | Submitted | None |
| 23350707 | Batch3 continuation, same four | 300,000 | Queued | `afterok:23350706` |
| 23350708 | Combined 24-stream analysis | 300,000 | Queued | `afterok:23350703:23350705:23350707` |

Seed labels for `run_0` through `run_3` are **25597939-25597942** for
batch1, **1713020953-1713020956** for batch2 and **1015237625-1015237628**
for batch3. Continuations inherit their start's RNG state and seed labels.
These are twelve additional independent streams, represented by six jobs.
Analysis combines the three new leaves with existing leaves
**22885157/22904262/22904264** and reuses MCMC **22780263**.

The expected result is
`/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/combined24x300_analysis_23350708/`.
The random campaign-directory suffix was not included in the supplied
submission output, so the machine-readable record leaves that field unset
(`-`): [reported_add12_to24_jobs_20261124.tsv](reported_add12_to24_jobs_20261124.tsv).

To inspect these jobs on UBELIX:

```bash
sacct -j 23350702,23350703,23350704,23350705,23350706,23350707,23350708 \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

The submission instructions below would create another fresh campaign if
repeated; the jobs above already represent the requested expansion.

## Submit on UBELIX

Sync the new submission driver and analysis launcher, together with the
existing `run_ubelix.sh`, template and imported analysis modules. Then run:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh
```

Equivalent explicit command:

```bash
bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh \
    22885157 22904262 22904264 22780263
```

The first three IDs are the existing four-stream NS leaves; the last is
the existing three-chain direct MCMC reference at beta=1.0. Existing NS
streams and their ancestors are read-only inputs. Their checkpoints are
not continued by this campaign. No new MCMC is submitted.

The saved `cpn_ns_N4` executable from existing leaf **22885157** supplies
the fresh runs; the driver checks that it reports N=4. A valid saved binary
needs no rebuild. Preflight validates all twelve existing raw histories,
their cumulative 300k depths, fresh/resume flags, N=4 logs, compatible
settings and distinct seeds. The three existing seed ranges are:

| Existing NS leaf | Streams | Seeds |
| --- | ---: | --- |
| 22885157 | 4 | 828968384-828968387 |
| 22904262 | 4 | 335358449-335358452 |
| 22904264 | 4 | 691294503-691294506 |

The submission driver allocates three new four-seed ranges using the system
random source. It rejects collisions with all twelve existing NS seeds,
the three MCMC seeds, and all other fresh seeds in this campaign. The full
24-stream seed plan is saved before the first submission.

## Jobs and resources

| Role | Independent new streams | Segment updates/stream | Cumulative updates | CPUs | Memory | Time limit |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| Batch1 fresh start | 4 | 150,000 | 150,000 | 4 | 512 MB/CPU | 12 h |
| Batch1 continuation | Same four | 150,000 | 300,000 | 4 | 512 MB/CPU | 12 h |
| Batch2 fresh start | 4 | 150,000 | 150,000 | 4 | 512 MB/CPU | 12 h |
| Batch2 continuation | Same four | 150,000 | 300,000 | 4 | 512 MB/CPU | 12 h |
| Batch3 fresh start | 4 | 150,000 | 150,000 | 4 | 512 MB/CPU | 12 h |
| Batch3 continuation | Same four | 150,000 | 300,000 | 4 | 512 MB/CPU | 12 h |
| Combined analysis | Existing12 + new12 | -- | 300,000 | 1 | 32 GB | 24 h |

There are **six simulation jobs representing twelve new streams**, plus
one analysis job. Three fresh batches can run in parallel. Each continuation
waits for its own start with `afterok`; analysis waits for all three new
leaves. Each start and continuation config has `num_ns_meas=150001`.
Continuations inherit the same four RNG states and seeds, use copied
checkpoints in their new job directory, and link to their parent history.
The scanner removes the repeated checkpoint row when joining segments.

Using the earlier measured L120 rate **0.172797222 seconds/update**,
150k updates project to **7.20 hours/stream**, and a fresh 300k stream to
**14.40 hours**. Twelve additional streams project to **172.8 aggregate
CPU-hours**, excluding initialization and overhead and assuming early-depth
rates persist. These are projections, not newly measured production times.
The 12-hour stage and 24-hour analysis allocations are time limits; queue
waits and CPU differences affect calendar time.

## Records and results

The submission driver prints the actual job IDs and creates:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/add12_to24_300k.<random>/
```

This contains `jobs.tsv`, `existing_inputs.tsv`, all 24 NS seeds in
`planned_seeds.tsv`, executable/source hashes, Slurm log paths,
`analysis_job_id.txt` and `analyze_command.txt`. The retry command submits
only the dependent analysis against the same six leaves. If submission
stops partway through, inspect `jobs.tsv` and the scheduler before retrying
the production driver: another invocation allocates another fresh campaign.

Simulation data are written under new job-specific directories:

```text
/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L120/job_<ID>/run_<0..3>/
```

Override the scratch root with `NS_SCRATCH=/absolute/path` when submitting.
The analysis result directory is:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L120_res/combined24x300_analysis_<ANALYSIS_ID>/
```

It records six NS leaf roots and MCMC 22780263 in `inputs.tsv`, the Git
revision and analysis source hashes. A `completed` marker is written only
after every analysis command succeeds. Outputs include:

- `depth.csv`: 24-stream depth checks at 180k/210k/240k/270k/300k, target
  betas 0.9/0.95/1.0, 200 whole-stream bootstrap replicates, seed 20261124.
  All 24 input histories must have exactly 300k cumulative updates.
- `mcmc_full/` and `mcmc_burn20000/`: reused reference histories and binning.
- `action_bins32_beta1p0_block512/`: conditional correlator comparison at
  beta=1.0, 32 bins, MCMC cut 20,000 MC steps and blocks of 512 measurements.
  Its plotted errors are marginal errors, as in `compare_action_bins.py`.

The combined NS live count is **24*50=1200**. Preserve the existing twelve-
stream analyses and robustness outputs as the comparison baseline. The
ideal statistical error reduction from 12 to 24 streams is about 1/sqrt(2)
if the streams are independent and similarly distributed; this does not
reduce a shared sampling bias. Review the 24-stream depth and conditional
results before interpreting any precision gain.

## Local verification

`bash N4_volume_benchmark/validate_L120_24stream_launchers.sh` runs local
Slurm/simulation/Python mocks. It checks all old history shapes, collisions
with each old seed group and fresh seeds, six simulation submissions and
dependencies, stage counts, fresh/resume flags, RNG inheritance, parent
links, 24-stream analysis routing, unchanged parents, and failure/partial-
submission guards. It produces no physics results and submits no cluster jobs.
