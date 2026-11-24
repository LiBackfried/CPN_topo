# N=21, L=72 UBELIX benchmark

Collected local and reported UBELIX results are in
[N21_benchmark_results](../N21_benchmark_results/README.md), including both
replacement analysis jobs, timing comparisons, observables and interpretation.

Fresh nested-sampling trial with two proposal counts, at source beta 0.6 and
theta 0. Each arm has ten independently seeded streams, 50 live points and
5,000 NS updates per stream (`num_ns_meas=5001`). Proposals per update are
15,500 (approximately 3L²) and 31,000. Every update also includes four
microcanonical sweeps, measurements and cooling to 50 sweeps at intervals of five.
Fresh initialization retains 20 heatbath sweeps and eight sweeps between live
points. These settings permit comparison with the recent local trials; their
adequacy for initialization and mixing remains to be established.

## Compile on UBELIX

First copy/sync the current simulation sources, `utils/`,
`analyze_nested_sampling.py` and this directory to the UBELIX checkout. The
new files may not yet be committed, so `git pull` alone might not transfer them.

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N21_L72_ubelix_benchmark/build_N21_ubelix.sh
module purge
module load OpenSSL/1.1
(./cpn_ns_N21 2>&1 || true) | grep -Fx 'Compiled with N = 21'
```

The helper starts from a clean module environment and loads `GCCcore/14.2.0`
and `OpenSSL/1.1`, then copies C sources to a temporary
build directory, sets N=21 there, bootstraps Autotools, configures and builds.
It adds the same monotonic NS-loop timer as the local benchmark. It creates
`cpn_ns_N21`, `cpn_ns_N21.build.log`, `cpn_ns_N21.build_info.txt` and
`cpn_ns_N21.sha256` in the repository root. It preserves the checkout's N header,
objects, `cpn_ns`, `cpn_ns_N4` and other executables. The no-input invocation
deliberately returns a nonzero status; the grep above checks its banner.
Do not simply rename an N=4 executable.

The compiler-only module avoids the MPI/libevent dependencies brought in by
`foss/2025a`; that stack needs OpenSSL/3 and warns when OpenSSL/1.1 replaces it.
OpenSSL/1.1 is retained for the simulation's existing MD5 API. The build records
its loaded modules in `cpn_ns_N21.build_info.txt`. Submission, simulation and
analysis scripts also reset their own module environments before loading their
requirements. Running them with `bash` or `sbatch` keeps these changes inside
their child shells; already-running jobs are unaffected.

The warning alone does not establish a compilation failure. A successful build
prints `Built .../cpn_ns_N21`; if it fails, inspect:

```bash
tail -n 60 cpn_ns_N21.build.log
```

The compiler version above follows the GCCcore-14.2.0 module identified in the
reported warning. If it cannot be loaded at the site, use
`module spider GCCcore/14.2.0` to inspect the site's module prerequisites.

## Submit

Run the submission driver with `bash`; it calls `sbatch` for each batch worker:

```bash
bash N21_L72_ubelix_benchmark/submit_ubelix.sh
```

This submits two NS jobs, each requesting ten single-threaded tasks, 2 GiB per
CPU and two hours, plus one dependent analysis job with one CPU, 8 GiB and two
hours. The analysis runs only after both simulations succeed. Existing account,
partition and QoS conventions are `gratis`, `epyc2`, `job_gratis`.
Both simulation jobs and the analysis job email `liane.backfried@unibe.ch`
on completion or failure (`--mail-type=END,FAIL`).
The default seeds are 21720001–21720010 and 21720101–21720110. These are distinct
between arms; repeating the driver deliberately repeats those seeds. Choose
a different `NS_SEED_BASE` if adding statistically independent campaigns.

The driver prints the campaign directory, simulation IDs, analysis ID and an
exact `sacct` command. Run that printed command to check allocations and status.
The two simulation allocations should request/allocate ten CPUs each; the
analysis requests one. For a running simulation, inspect its allocation with
`scontrol show job JOB_ID`. Submit workers with `sbatch`, never `bash` or `./`.
Inherited `SBATCH_*` overrides are cleared by the driver.

For a shorter 100-update cluster timing smoke test:

```bash
NS_SEED_BASE=21721001 bash N21_L72_ubelix_benchmark/submit_ubelix.sh 100
```

This still submits both ten-stream arms and dependent analysis. It tests the
workflow and cluster runtime; it is too short to assess sampling quality.
The 31,000-proposal workload has not yet been timed locally. The measured local
15,500-proposal workload suggests about 7.3 minutes per 5,000-update stream;
this is an extrapolation, not an UBELIX runtime measurement.

## Outputs and analysis

Output is created on scratch under a new directory per submission:

```text
/scratch/network/users/lb25v444/out_data/ns_N21_L72_benchmark.<unique>/
  jobs.tsv
  snapshot/                    executable, input, analysis and worker snapshots
  job_<simulation_ID>/run_0/   through run_9, one working directory per stream
  analysis_<analysis_ID>/
    REPORT.md
    timings.csv
    timing_summary.csv
    observable_comparison.csv
    p15500/                   weighted estimates, errors and four PNG plots
    p31000/
    completed
```

Build/source hashes and exact executable/analysis snapshots preserve provenance
when the checkout changes. Each job and stream receives a completion marker only
after its output checks pass. Existing job directories cannot be reused.
All live checkpoints are retained for later audit or separately prepared
continuations; this workflow always starts fresh and never modifies old runs.

The report separates loop wall time, loop CPU time, initialization CPU time,
process wall time and peak resident memory. It groups different CPU models
separately. Raw acceptance data, cutoffs, configurations and cooling histories
remain available. Before reporting, it validates finite output, row counts,
cooling steps, monotone cutoffs, final live-energy cutoffs and all twenty seeds.
It does not recompute energies from saved field configurations; numerical
energy consistency was checked separately in the local benchmark.

Each arm is analyzed separately with `--cpn-n 21` at its source beta, using 500
whole-stream bootstrap replicates. No raw bootstrap replicas are saved. The
observable comparison reports differences and combined bootstrap errors;
agreement alone does not establish unbiased sampling. A direct MCMC reference,
initialization study, fixed-cutoff mixing tests and beta-reweighting depth scan
are separate follow-up work.

If analysis fails after simulations complete, inspect its `.err`/analysis logs,
then submit the saved analysis worker again (replace CAMPAIGN with the printed
absolute campaign directory):

```bash
sbatch --chdir=CAMPAIGN --output=CAMPAIGN/analysis_%j.out \
  --error=CAMPAIGN/analysis_%j.err \
  "$PWD/N21_L72_ubelix_benchmark/analyze_ubelix.sh" CAMPAIGN
```

Each retry writes a new `analysis_<job_ID>` directory. If a simulation fails,
the `afterok` analysis remains pending with an unsatisfied dependency; inspect
and cancel that dependent analysis before starting a replacement campaign.

### Repair the skipped second-arm analysis

An earlier worker allowed `srun` to consume the input of its manifest-reading
loop, skipping the 31,000-proposal arm and failing at the comparison stage with
missing `p31000/results.json`. The fixed worker reads the manifest through its
own descriptor, gives `srun` no standard input, and checks each arm's result
before proceeding. Regression validation reproduces the old failure with an
input-consuming mock step and verifies the fix.

For the reported 100-update campaign, sync the corrected `analyze_ubelix.sh` to
the repository on UBELIX and submit only analysis again:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
campaign=/scratch/network/users/lb25v444/out_data/ns_N21_L72_benchmark.uZevELp8
sbatch --chdir="$campaign" --output="$campaign/analysis_%j.out" \
  --error="$campaign/analysis_%j.err" \
  "$PWD/N21_L72_ubelix_benchmark/analyze_ubelix.sh" "$campaign"
```

Use the corrected repository worker, rather than the older worker inside the
campaign snapshot. Simulation and analysis-source snapshots remain unchanged,
so their existing integrity checks still apply. Each retry also saves the actual
submitted worker as `analysis_worker.sh` plus its hash in the new output folder.
No recompilation or simulation rerun is needed. The same repair applies to
`ns_N21_L72_benchmark.5NegZsTv` after both of its simulation jobs complete.

## Local checks

```bash
bash N21_L72_ubelix_benchmark/validate_launchers.sh
```

This runs shell syntax/LF checks and mocked submission/worker integration checks,
including wrong-N, incorrect allocations, repeated outputs, duplicate seeds and
partial-submission failures. It does not contact Slurm or submit real jobs.

The prepared workflow passed those checks, Python compilation, and all 38
repository tests in `fpaction2`. A private Ubuntu-24.04 WSL compilation using
this build helper verified N=21, preserved a pre-existing header/generic binary,
and completed a real two-update L=72 smoke run with the expected data/cooling
rows and monotonic timing output. The WSL check disables MD5 because its
OpenSSL development headers are unavailable; actual UBELIX module loading and
Slurm execution remain untested locally. To repeat that private build check:

```bash
bash N21_L72_ubelix_benchmark/validate_build_wsl.sh
```
