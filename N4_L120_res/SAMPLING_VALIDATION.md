# L120 source initialization and proposal-count checks

Prepared locally on 2026-11-25 at the user's request; no UBELIX jobs have
been submitted from this checkout. The proposed target-MCMC error audit
(previous step 1) is dropped. The two checks below implement steps 2 and 3.

## Run on UBELIX

Sync the new scripts and Python analysis to the existing repository, then
from its root on a login node run:

```bash
bash N4_volume_benchmark/submit_L120_sampling_validation_ubelix.sh
```

This submits nine jobs: source pilot and dependent analysis; two independent
four-stream NS batches, each with three dependent 100k stages; and a final
proposal comparison after both 300k leaves. Source and NS checks can run
concurrently. To submit just one check use `source` or `ns` as the argument.
Do not rerun the helper to retry an individual failed analysis: each invocation
creates fresh seeds and submissions. Inspect its `jobs.tsv`; the NS analysis
retry command is saved in the campaign directory.

Required scratch inputs are the completed baseline NS leaves
**22885157, 22904262, 22904264, 23350703, 23350705, 23350707** and MCMC
**22780263**. Their existing ancestor directories must remain available for
analysis. The helper reuses saved binaries from NS 22885157 and MCMC
22780263, verifying that both report N=4. No rebuild is needed for these
input-parameter changes. Override the MCMC binary with an absolute
`MCMC_EXECUTABLE` path if its saved copy is unavailable.

Campaign records live under `N4_L120_res/sampling_validation.<random>/`:
job IDs, dependencies, allocated seeds, settings, executable/source hashes,
Git revision and Slurm logs. `planned_seeds.tsv` records all 24 baseline seeds
and reserves twelve new ones, including unused groups in a single-check
submission. New seeds are checked against all baseline and reference seeds.
`NS_SCRATCH` can override the existing scratch base.

## Source beta=0.7: warmup and live-point spacing

The pilot uses four independent regular MCMC chains at N=4, L=120,
beta=0.7, theta=0: **two cold (`start 0`) and two hot (`start 1`)**. Each
runs **10,000 MC cycles**, measures every cycle and records charges through
50 cooling sweeps. It requests four CPUs, 512 MiB/CPU and two hours. To
prepare a longer pilot, set `INIT_PILOT_STEPS` before submission.

The single-replica update schedule uses four microcanonical sweeps followed
by a heatbath sweep, matching the source live-point initializer's sweep
schedule. Regular MCMC also explicitly normalizes fields every cycle; this
is a statistical initialization check, not a bitwise replay of the NS
initializer. No C implementation changes are involved.

The current initializer burns 20 cycles and stores its first live point
after the next cycle, then every eight cycles. Thus its 50 slots are
**21, 29, ..., 413**. The analysis compares those windows against late slots
2001, 2009, ..., 2393 and writes:

- `histories_early.png`, `histories_full.png`: action density, G0, Gk and Q.
- `cut_scan.csv`, `binning.csv`: per-chain and hot/cold pooled estimates
  after cuts 0/20/100/500/1000/2000, with a powers-of-two block scan.
  The cut summary uses the largest available block at most 128 measurements;
  inspect the complete block scan before interpreting those errors.
- `autocorrelation.csv`, `autocorrelation_curves.csv`, `autocorrelation.png`:
  per-chain ACFs after 2000 cycles for action, G0, Gk, Q and Q², integrated
  autocorrelation times, chosen windows and rho(8).
- `live_spacing_windows.csv`: descriptive means and standard deviations of
  initial and late 50-point samples, preserving hot/cold labels.

The convention is tau_int = 1/2 + sum rho(t), in MC cycles. A self-consistent
window W >= 10 tau_int is used, searching up to min(N/10, 2000) lags.
The `reliable` flag additionally requires N >= 200 tau_int. These are
heuristics; they do not establish stationarity. Constant series have undefined
tau, rather than being classified as independent. Assess hot/cold agreement,
drift and cut stability separately from decorrelation. A small rho(8) alone
does not prove independence of the full live ensemble or good constrained
sampling at deeper NS levels.

Raw output: `$NS_SCRATCH/mcmc_120_N4_beta0p7_initpilot/job_<pilot>/`.
Results: `N4_L120_res/source_init_<pilot>_analysis_<analysis>/`.

## Separate NS proposal control: 86400 versus 172800

Keep initialization fixed at **20/8**, so this comparison changes only the
constrained proposal count. It is independent of the source-pilot outcome;
the helper does not silently adjust initialization based on that outcome.

The control has **eight fresh independent streams**, each with 50 live
points and **172800 proposals per NS update (12L²)**. Each reaches 300k
updates in three 100k stages. Every stage requests four CPUs, 512 MiB/CPU
and 12 hours; there are two independent four-stream batches. Continuations
copy validated checkpoints into new job directories, inherit executable,
settings and RNG state, and preserve the parent. Keep all three stages.

The earlier measured 86400-proposal rate was 0.172797222 s/update. At that
rate 100k takes 4.80 h; doubling the entire cost would give 9.60 h per 100k,
or 28.8 h per 300k stream and 230.4 aggregate CPU-hours for eight streams.
This is a planning projection, not a measured timing for 172800 proposals;
the 12-hour requests provide headroom over that projection. Check actual
timing after the first stage, especially as the energy cutoff deepens.

The dependent analysis compares **baseline24 at 86400** with **control8 at
172800**, reusing the same beta=1.0 MCMC reference, cut 20000 and block 512
measurements. The cohorts remain separate; this does not create a merged
32-stream production ensemble. Both use a common NS energy cutoff and the
same 32 MCMC-quantile action bins over the central 99% range. Outputs:

- `observables.csv`: canonical observables, NS bootstrap SE and MC residuals.
- `baseline24/`, `control8/`: conditional G0/Gk plots and tables, covariance,
  simultaneous intervals and the approximate joint bootstrap diagnostic.
- `proposal_differences.csv`: baseline minus control, using independent NS
  errors; the shared MCMC error cancels. Here `old` means baseline24 and
  `new` means control8.
- `control_depth.csv`: 240k/270k/300k checks of beta=1.0 coverage.
- `inputs.json`, source hashes and revision for provenance.

Bootstrap settings remain 200 whole-stream draws and 1000 joint draws.
Interpret the original conditional G0 residual and its change together with
the full joint comparison and integrated observables. Eight control streams
give a screening test with larger uncertainty than baseline24; a null shift
does not establish proposal-count convergence. If the source pilot shows
inadequate warmup or spacing, a separate initialization-control NS study
will be needed before combining new data into production estimates.

Raw output: `$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L120/job_<stage>/`.
Results: `N4_L120_res/proposals172800_<first-leaf>_analysis_<analysis>/`.

## Earlier proposal-count evidence

At **L38**, source beta=0.7 reweighted to beta=1.0, the completed 35k-depth
comparison gave:

| Proposals/update | Streams | xi_L² |
| --- | ---: | ---: |
| 4332 = 3L² | 16 | 115.32 ± 2.16 |
| 8664 = 6L² | 24 | 105.55 ± 3.09 |
| 12996 = 9L² | 12 | 106.37 ± 3.04 |
| Direct MCMC | 3 | 107.45 ± 0.43 |

Doubling to 6L² improved integrated agreement. The 9L² result showed no
clear further improvement. These are differently seeded ensembles with
different stream counts, not paired measurements. Conditional-bin features
remained: the 9L² Gk comparison had two marginal bins above 3 SE (maximum
about 3.99). This supports sensitivity testing, not a general proof of
constrained-chain convergence or a guarantee at L120.

Sources: [baseline depth](../N4_L38_res/stoc12996.pXcxr0/depth_baseline16.csv),
[6L² depth](../N4_L38_res/stoc12996.pXcxr0/depth_stoc8664_24.csv),
[9L² depth](../N4_L38_res/stoc12996.pXcxr0/depth_stoc12996_12.csv),
[MCMC binning](../N4_L38_res/stoc12996.pXcxr0/mcmc_burn20000/binning.csv)
(pooled block 128), and the adjacent `action_bins32/` tables.

The L66 proposal-doubling pilot and L120 43200-versus-86400 pilot were
timing checks. In particular, L120's 200/2000-update timings do not provide
a production-depth physics comparison; 86400-to-172800 at 300k is new.

## Local checks

```bash
bash tests/test_sampling_validation_launchers.sh
python -m unittest discover -s tests -p test_sampling_validation.py -v
```

The shell test uses mocked Slurm commands and executables. It checks nine
submissions, seeds/collisions, source hot/cold configurations, all six NS
stages, continuation flags and parent links, preserved checkpoints,
dependencies and failure records. Python tests exercise ACFs of white noise
and a known AR(1) process, source-pilot output, and separate proposal cohorts.
