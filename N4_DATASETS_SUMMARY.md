# N=4 dataset inventory

Updated: 2026-11-18. All lattice sizes below mean a two-dimensional `L x L`
lattice in the CP^3 model (`N=4`). This inventory combines saved local results,
launchers, and previous chats. It records historical production evidence;
current UBELIX file availability and Slurm state were not checked remotely.
Unknown job IDs are left explicit.

The completed seven-beta L22/L38/L66 analysis is now copied to
`N4_L66_res/volume_scan.T1n611/`: analysis jobs `22622025`, `22622026`,
`22622027`, and combined comparison `22622028`. It uses 100 selected L22
streams, 24 L38 streams at 8,664 proposals/update, and 12 L66 streams at
26,136 proposals/update. All seven requested betas and three direct MCMC
references are present. The copied comparison identifies the previously
unknown L22 MCMC job as **21347214**. See the adjacent `RESULTS_REVIEW.md`
for numerical checks and limitations. Remote Slurm state was not queried.

## Overview

| Dataset | L | Simulation beta | Independent streams/chains | Length per stream/chain | UBELIX simulation job IDs | Evidence/status |
| --- | ---: | ---: | ---: | --- | --- | --- |
| Main NS production, grown from 10 to 800 streams | 22 | 0.7 | 800 | 50,000 NS updates | 32 jobs, listed below | Produced; saved analyses cover all 800 streams |
| Original NS depth study | 38 | 0.7 | 4 | 35,000 cumulative NS updates | `22097065`, `22118868`, `22119560`, `22120845`; earlier pilot ID unknown | Produced; these are successive segments of the same four streams |
| Fresh NS, 4,332 stochastic proposals/update | 38 | 0.7 | 12 | 35,000 NS updates | `22133588`, `22133589`, `22133590` | Produced; four streams per job |
| NS with doubled proposals, 8,664/update | 38 | 0.7 | 12 | 35,000 NS updates | `22320950`, `22320951`, `22320952` | Produced; four streams per job |
| Additional NS with doubled proposals, 8,664/update | 38 | 0.7 | 12 | 35,000 NS updates | `22583507`, `22583508`, `22583509` | Produced; combined 24-stream analysis copied in `volume_scan.T1n611` |
| Direct MCMC reference | 38 | 1.0 | 3 | 1,000,000 MC steps = 100,000 measurements | `22121710` | Produced; saved MCMC analyses available |
| L66 NS, 26,136 proposals/update | 66 | 0.7 | 12 | 110,000 NS updates | `22587433`, `22587434`, `22587435` | Produced; copied campaign and seven-beta analyses available |
| L66 direct MCMC reference | 66 | 0.9 | 3 | 1,000,000 MC steps = 100,000 measurements | `22587511` | Produced; copied MCMC binning and matched comparisons available |
| NS timing campaign, original and optimized code | 22, 38 | 0.7 | 4 per job | 200 and 2,000 NS updates | Successful campaign IDs not recovered | Completed timing report available |
| NS timing campaign, optimized code | 66, 90, 120 | 0.7 | 4 per job | 200 and 2,000 NS updates | Successful campaign IDs not recovered | Timing pilots produced; distinct from the newly submitted L66 campaign |
| Regular MCMC production | 22 | 0.7 | 3 | 10,000,000 MC steps = 1,000,000 measurements | `21347214` | Produced; identified and analyzed by comparison job `22622028` |

NS production uses 50 live points per stream. The L=22 production has 1,500
stochastic proposals per NS update; the original and fresh L=38 streams have
4,332, and the doubled-proposal ensemble has 8,664. Production families above
use theta=0. Reweighting target betas are analysis settings, not additional
independently generated datasets.

## L=22: 800-stream NS production

Common UBELIX base:

```text
/scratch/network/users/lb25v444/out_data/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/
```

Each row lives at `job_<SIMULATION_JOB_ID>/run_<RUN_ID>/` below that base.
Some older saved JSON files use `/rs_scratch/users/lb25v444/out_data/` instead.
The job/run mapping is independently recorded in
`sh_files/analyze_N4_L22_ubelix.sh` and the saved analysis `results.json` files.

| L | Run IDs | Streams | UBELIX simulation job ID |
| ---: | --- | ---: | --- |
| 22 | 0-9 | 10 | `19135775` |
| 22 | 10-49 | 40 | `19678209` |
| 22 | 50-74 | 25 | `19692937` |
| 22 | 75-99 | 25 | `19692936` |
| 22 | 100-124 | 25 | `20008149` |
| 22 | 125-149 | 25 | `20008651` |
| 22 | 150-174 | 25 | `20010266` |
| 22 | 175-199 | 25 | `20008148` |
| 22 | 200-224 | 25 | `20388977` |
| 22 | 225-249 | 25 | `20388978` |
| 22 | 250-274 | 25 | `20389384` |
| 22 | 275-299 | 25 | `20388976` |
| 22 | 300-324 | 25 | `20525014` |
| 22 | 325-349 | 25 | `20525015` |
| 22 | 350-374 | 25 | `20525016` |
| 22 | 375-399 | 25 | `20525009` |
| 22 | 400-424 | 25 | `20684460` |
| 22 | 425-449 | 25 | `20684461` |
| 22 | 450-474 | 25 | `20684462` |
| 22 | 475-499 | 25 | `20686257` |
| 22 | 500-524 | 25 | `20687600` |
| 22 | 525-549 | 25 | `20687618` |
| 22 | 550-574 | 25 | `20687905` |
| 22 | 575-599 | 25 | `20688780` |
| 22 | 600-624 | 25 | `20689657` |
| 22 | 625-649 | 25 | `20690092` |
| 22 | 650-674 | 25 | `20690588` |
| 22 | 675-699 | 25 | `20691674` |
| 22 | 700-724 | 25 | `20691875` |
| 22 | 725-749 | 25 | `20692744` |
| 22 | 750-774 | 25 | `20692746` |
| 22 | 775-799 | 25 | `20684452` |

Total: 800 independently seeded streams, run IDs 0-799, with 40,000,000 NS
updates overall. The 10-, 50-, 100-, 200-, 300-, 400-, and 800-stream analysis
families are overlapping pools of this production, not separate simulations.

A local copy of runs 750-774 is in `../data_N4_UBELIX/`. These 25 streams
belong to simulation job `20692746`; the stream-length and reweighting studies
reuse them. Their local configs specify `size 22 22`, beta 0.7, 50 live points,
1,500 proposals, and `num_ns_meas 50001`.

### Saved L=22 analysis jobs

These IDs identify analysis allocations, distinct from the simulation IDs
above. Results are under
`analysis_results/ns_constraint_22_N4_beta0p7_<COUNT>x50000_stoc1500/job_<ANALYSIS_ID>/`.

| Streams | Target beta | UBELIX analysis job IDs |
| ---: | --- | --- |
| 10 | Source 0.7 | `19671986` |
| 50 | Source 0.7 | `19686350` |
| 100 | Source 0.7 | `20007180` |
| 200 | Source 0.7 | `20028915`, `20388359` |
| 300 | Source 0.7 | `20446648`, `20508089` |
| 400 | Source 0.7 | `20649450` |
| 800 | Source 0.7 | `20793993`, `21042450` |
| 800 | 0.68 | `21098598` |
| 800 | 0.69 | `21092808` (100 bootstraps), `21098603` (500 bootstraps) |
| 800 | 0.71 | `21098616` |
| 800 | 0.75 | `21098620` |

The local prefix study is in `analysis_results/N4_L22_stream_length_20261106/`
and reuses runs 750-774 at target betas 0.68, 0.69, 0.70, 0.71, and 0.75.
It has no separate UBELIX simulation job.

## L=38: NS depth study and additional ensembles

Common UBELIX base:

```text
/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L38/
```

Each job has four streams, `run_0` through `run_3`. The original four were
extended through the following checkpoints:

| L | UBELIX simulation job ID | Cumulative NS updates per stream | Relationship |
| ---: | --- | ---: | --- |
| 38 | Earlier optimized timing-pilot ID unknown | 2,000 | Starting checkpoint for the original four streams |
| 38 | `22097065` | 5,000 | Continued the 2,000-update pilot |
| 38 | `22118868` | 10,000 | Continued `22097065` |
| 38 | `22119560` | 20,000 | Continued `22118868` |
| 38 | `22120845` | 35,000 | Continued `22119560`; final original four-stream dataset |

The four original depth exports are saved locally in the checkout root as
`L38_depth_22097065.csv`, `L38_depth_22118868.csv`,
`L38_depth_22119560.csv`, and `L38_depth_22120845.csv`. Later fresh and pooled
exports are present under `N4_L38_res/`; copies of `L38_depth_fresh12.csv`
and `L38_depth_combined16.csv` also remain in the checkout root.

| L | Additional ensemble | UBELIX simulation job IDs | Streams | Saved local analysis |
| ---: | --- | --- | ---: | --- |
| 38 | Fresh, 4,332 proposals/update | `22133588`, `22133589`, `22133590` | 12 | `N4_L38_res/L38_depth_fresh12.csv` |
| 38 | Original four + fresh twelve, 4,332 proposals/update | `22120845` plus the three IDs above | 16 total, overlapping the preceding datasets | `N4_L38_res/L38_depth_combined16.csv`, `L38_correlators_combined16.csv` |
| 38 | Fresh, 8,664 proposals/update | `22320950`, `22320951`, `22320952` | 12 | `N4_L38_res/L38_depth_2xstoc12.csv` |
| 38 | Additional fresh, 8,664 proposals/update | `22583507`, `22583508`, `22583509` | 12 submitted | Dependent analysis job `22583510`; outputs expected under `N4_L38_res/extra8664.m3YXfE/` |

The produced streams reached 35,000 updates each. Baseline-proposal scans cover
target beta 0.8, 0.9, and 1.0; the doubled-proposal export covers target beta
1.0. There are 28 independent L=38 NS streams in total: 4 original + 12 fresh
at 4,332 proposals, and 12 fresh at 8,664 proposals. Continuations and pooled
analyses do not add independent streams.

On 2026-11-18 the user confirmed submission of twelve additional independent
streams in jobs `22583507`, `22583508`, and `22583509`, each requesting
35,000 updates at 8,664 proposals per NS update. Their simulation data paths
are `job_<ID>/run_<0..3>/` under the common UBELIX base above. If all twelve
complete, the doubled-proposal pool will contain 24 streams and the total
across both L=38 proposal settings will be 40 independent streams.

Analysis job `22583510` was submitted with an `afterok` dependency on all
three new simulation jobs. It analyzes the new twelve, previous twelve,
combined 24 doubled-proposal streams, baseline sixteen streams, and direct
MCMC reference. Its analysis and submission records are saved in the Git
checkout at:

```text
/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/N4_L38_res/extra8664.m3YXfE/
```

That directory contains the submission manifest and retry command. Expected
analysis outputs include `depth_fresh12.csv`, `depth_previous12.csv`,
`depth_combined24.csv`, `depth_baseline16.csv`, `action_bins32/`, and
`mcmc_burn20000/`. Completion of these four new jobs has not been verified.

The saved 16-bin comparisons in `N4_L38_res/action_bins/stoc4332/` and
`stoc8664/` reuse these ensembles and MCMC job `22121710`. The 32-bin
analysis is prepared in `N4_volume_benchmark/analyze_L38_action_bins_ubelix.sh`;
no completed `N4_L38_res/action_bins_32bins/` output was found locally.

## L=66: submitted campaign

On 2026-11-18 the user confirmed MCMC job `22587511`, NS simulation jobs
`22587433`, `22587434`, `22587435`, and dependent analysis job `22587436`.
Completion and current Slurm state have not been checked remotely. The
three NS simulation jobs have four streams each, for twelve independent
streams; the analysis job contributes no simulation streams.
The intended simulation setup is N=4, L=66, source beta=0.7,
50 live points, 26,136 proposals/update and 110,000 updates per stream.
Reweighting targets extend through beta=1.0. The direct reference has
beta=0.9, three chains and 100,000 raw measurements per chain.

NS simulation data use
`/scratch/network/users/lb25v444/out_data/ns_N4_beta0p7_volume_benchmark/L66/job_<ID>/run_<0..3>/`.
MCMC data use
`/scratch/network/users/lb25v444/out_data/mcmc_66_N4_beta0p9_3x100k/job_22587511/run_<0..2>/`.
All L66 analysis outputs and job records belong in repository `N4_L66_res/`;
see `N4_L66_res/README.md` and `reported_jobs_20261118.tsv` there.

## Direct MCMC

| L | Beta | UBELIX simulation job ID | Dataset and location | Status |
| ---: | ---: | --- | --- | --- |
| 66 | 0.9 | `22587511` | `/scratch/network/users/lb25v444/out_data/mcmc_66_N4_beta0p9_3x100k/job_22587511/run_<0..2>/` | Produced; copied binning and matched NS comparison available |
| 38 | 1.0 | `22121710` | `/scratch/network/users/lb25v444/out_data/mcmc_38_N4_beta1p0_3x100k/job_22121710/run_<0..2>/` | Produced: three chains, 100,000 measurements each before cuts |
| 22 | 0.7 | `21347214` | `/scratch/network/users/lb25v444/out_data/mcmc_22_N4_beta0p7_3x1M/job_21347214/run_<0..2>/` | Produced; copied pooled binning and NS comparison in `N4_L66_res/volume_scan.T1n611/` |

L=38 analysis copies are in `N4_L38_res/mcmc_analysis/`,
`mcmc_analysis_burn20000/`, and `mcmc_correlators_burn20000/`. The latter two
discard 20,000 MC steps and retain 98,000 measurements per chain. They are
analyses of the same three chains, not additional generated datasets.

## Timing and local validation data

The completed UBELIX timing campaign used beta 0.7, four matched chains per
job, and lengths of 200 and 2,000 NS updates. Original-code timings exist at
L=22 and 38; optimized timings exist at L=22, 38, 66, 90, and 120. Successful
job IDs were not included in the completed timing report supplied in the
previous chat. The campaign's `cpn_ns_timing.*/jobs.tsv` on UBELIX is the place
to recover them. See `N4_volume_benchmark/PERFORMANCE.md` and `time_ubelix.sh`.

An earlier timing attempt mentioned long-job IDs `22033002` (L=22 original),
`22033006` (L=38 original), `22033011` (L=22 optimized), `22033014` (L=38
optimized), `22033017` (L=66 optimized), `22033022` (L=90 optimized), and
`22033025` (L=120 optimized). An `output_root: unbound variable` launch failure
was subsequently reported for step `22033009.0`. These IDs describe the
earlier unsuccessful/incomplete attempt and must not be assigned to the
successful timing results.

Additional local datasets, without UBELIX job IDs:

| L | Dataset | Local evidence |
| --- | --- | --- |
| 22 | N=4 NS runtime smoke test, beta 0.6, two repetitions of five NS updates, 15,500 proposals/update | `N4_L22_runs/smoke_runtime_20261020/` |
| 22 | Regular-MC runtime/checkpoint benchmark, beta 0.7, three seeds, 20,000 MC steps per timing run | `out_data_mc_N4_L22_benchmark_20261106/` |
| 22, 38, 66, 90, 120 | NS optimization timing and validation; matched original/optimized timing at 22 and 38, optimized timing at all five sizes | `out_data_cpn_ns_perf/` reports/scripts and `N4_volume_benchmark/PERFORMANCE.md`; raw runs were on WSL |

Short unit-test and launcher-smoke outputs are validation artifacts rather
than independent physics production datasets. No completed physics-production
ensemble at L=66, 90, or 120 was identified in the reviewed files or chats.

## Sources checked

- `sh_files/analyze_N4_L22_ubelix.sh`: all 32 simulation job IDs and run ranges.
- `analysis_results/**/results.json` for N=4: recorded simulation input paths,
  lattice sizes, stream counts, lengths, source betas, and analysis settings.
- `N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/README.md` and
  `../data_N4_UBELIX/run_750/input.conf`: L=22 setup and copied-stream identity.
- `N4_volume_benchmark/README.md`, `PERFORMANCE.md`, and
  `analyze_L38_action_bins_ubelix.sh`: L=38 ensembles, MCMC reference, and timings.
- Original `L38_depth_22*.csv` files in the checkout root, plus saved CSVs and
  plots under `N4_L38_res/`.
- Previous chat **Optimize N=4 nested sampling**
  (`01a1d0b4-63cf-7392-be14-bb0a253822f3`): original continuation sequence,
  completed timing report, MCMC job, and user-supplied fresh-ensemble IDs,
  including the latest updates through 2026-11-18.
- Previous chat **Benchmark regular MC at N=4**
  (`01a1b12c-5e6d-73c0-b641-5305b3ef32ef`): L=22 MCMC setup; no confirmed
  UBELIX submission/result in that chat.
