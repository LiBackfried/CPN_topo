# L120 eight additional streams to 300k

This adds **eight fresh independent N=4, L120 NS streams**, source
beta=0.7 and theta=0, to the four completed streams in job **22885157**.
All twelve streams will have 300,000 NS updates, 50 live points and
86,400 stochastic proposals per update. The existing beta=1.0 MCMC
reference **22780263** is reused. The four existing NS streams are
read-only inputs and are not extended or rerun.

## Submit on UBELIX

Sync the new submission driver and combined-analysis launcher to the
UBELIX checkout. From the CPN_topo root:

```bash
bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh
```

The equivalent explicit command is:

```bash
bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh 22885157 22780263
```

The driver submits two four-stream batches. Each batch starts fresh for
150k updates, then has an `afterok` continuation for another 150k:

| Role | Streams | Segment updates per stream | Cumulative updates | CPUs | Wall-time request |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fresh batch 1 start | New 4 | 150,000 | 150,000 | 4 | 12 h |
| Fresh batch 1 leaf | Same 4 | 150,000 | 300,000 | 4 | 12 h |
| Fresh batch 2 start | New 4 | 150,000 | 150,000 | 4 | 12 h |
| Fresh batch 2 leaf | Same 4 | 150,000 | 300,000 | 4 | 12 h |
| Combined analysis | Existing 4 plus new 8 | — | 300,000 | 1 | 12 h |

These are **eight additional independent streams**, represented by four
simulation jobs, not sixteen new streams. The two starts can run in
parallel, as can their descendant leaves. Analysis waits for both new
leaves; the existing NS and MCMC inputs must already be completed.
Each simulation task is single-threaded with 512 MB. Analysis has 16 GB.
Submit batch workers with `sbatch`; the driver itself is run with `bash`.

At the measured early pilot rate of 0.172797222 s/update, one 150k
segment projects to 7.20 hours per stream and a full fresh 300k stream
to 14.40 hours, excluding initialization and other overhead. The additional
eight streams project to about 115.2 aggregate CPU-hours. Twelve-hour
segment requests provide headroom. These are estimates, not new measured
full-run times; queuing between stages may increase calendar time.

## Settings and preflight

Fresh streams use `start=1`, `rng_start=0`, 20 initial MC burn-in steps,
spacing eight between initial live points, four microcanonical sweeps,
normalization every step, and 50 cooling sweeps measured every five.
The saved N=4 executable from job 22885157 is used for both new batches,
so a rebuild is unnecessary. No existing checkpoint configuration is
copied into a fresh start; only its executable/settings are reused.

Before any submission the driver validates:

- The completed four-stream existing ensemble and its saved N=4 executable.
- All continuation histories back through jobs 22860149 and 22780262,
  requiring exactly 300k cumulative updates per existing stream.
- Consistent settings, seeds and start/resume flags, and nonempty raw
  analysis inputs and N=4 logs for every existing segment.
- The completed three-chain L120 beta=1.0 MCMC reference and its N=4 logs.
- Exact agreement between the existing ensemble settings and the transformed
  fresh template, except for seeds, segment length and fresh/resume flags.

Eight new seeds are allocated in two four-seed blocks before submission.
They are positive, in the ran2 range, and checked against each other,
the four existing NS seeds and the MCMC seeds. They are saved explicitly
for reproducibility. Inherited `SBATCH_*` overrides are cleared, and
fresh NS parameters are set explicitly for each start job.

Continuation jobs clear inherited NS overrides and inherit their start
job's RNG states, seed labels, settings and executable. The generic
launcher validates all live configurations, live energies and RNG state
before launching any chain, and copies checkpoints to a new job directory.
Both segments use `num_ns_meas=150001`. After removing the repeated
boundary measurement, each joined stream has 300k updates. The two
continuations do not count as new independent streams.

## Records and outputs

The driver creates repository `N4_L120_res/add8_300k.XXXXXX/` containing:

- `jobs.tsv`: four new simulation IDs and the analysis ID, paths, segment
  and cumulative lengths, seed bases and dependencies.
- `existing_inputs.tsv`: existing NS and MCMC IDs/paths.
- `planned_seeds.tsv`: twelve independent NS seed labels, four existing
  and eight new. Continuation segments do not add duplicate rows.
- `existing_executable_sha256.txt`, Slurm logs, `analysis_job_id.txt`
  and the saved `analyze_command.txt`.

Raw runs remain under
`${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}/ns_N4_beta0p7_volume_benchmark/L120/job_<ID>/run_<0..3>/`.
Use `NS_SCRATCH` if the existing campaign uses another scratch parent.
Every stream has its own working directory and output reuse is rejected.
Keep all original NS ancestors and both new start-job directories: the
analysis needs their measurements and relative `parent_run` links.

After submission, inspect all five allocations:

```bash
sacct -j <START1>,<LEAF1>,<START2>,<LEAF2>,<ANALYSIS> \
    --format=JobID,JobName%35,State,AllocCPUS,Elapsed,ExitCode
```

Require four CPUs per simulation job and one for analysis. A partial
submission leaves successful jobs recorded and does not cancel them.
Inspect the manifest before retrying the driver; rerunning it submits
another eight new streams. If only analysis submission fails, use the
saved retry command after checking the existing job IDs.

## Combined analysis

Analysis results go to repository
`N4_L120_res/combined300_ns22885157_analysis_<ANALYSIS_ID>/` with default
inputs. Only the existing NS leaf and the two new NS leaves are passed.
The scanner follows ancestors, drops repeated boundary measurements,
checks common settings and distinct seeds, and compares common prefixes
at 180k, 210k, 240k, 270k and 300k. The explicit 300k prefix prevents
silently accepting a shorter shared dataset.

The analysis uses beta=0.9, 0.95 and 1.0 with 200 paired whole-stream
bootstrap replicates, remerging by energy and recomputing weights for
every draw. The merged live-point count is 12*50=600; quadrature ESS
is not an independent-sample count.

Outputs include `depth.csv`, MCMC histories/histograms/binning with no
cut and with a provisional 20,000-MC-step cut, and
`action_bins32_beta1p0/` for a matched 32-bin correlator comparison at
300k, beta=1.0. That comparison uses MCMC blocks of 128 measurements
and 200 NS bootstrap replicates. The `completed` marker is written only
after all analyses succeed.

To rerun analysis independently from the UBELIX repository root:

```bash
sbatch N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh \
    22885157 <FRESH_LEAF1> <FRESH_LEAF2> 22780263
```

More streams improve the available statistical evidence but do not
guarantee a particular error reduction or establish constrained mixing.
Longer initialization or increased proposals belong in separate validation
ensembles. Inspect the conditional correlator bins as well as integrated
means, especially in view of the L90 Gk-bin differences.

## Local verification

```bash
bash N4_volume_benchmark/validate_L120_300k_launchers.sh
```

The check uses Slurm/Python/simulation mocks. It verifies existing
histories, N=4 logs, twelve distinct seeds, staged dependencies,
generated configs/update counts/parent links, parent immutability,
analysis routing, failure guards and partial-submission records. It
submits no remote jobs and generates no scientific simulation results.
