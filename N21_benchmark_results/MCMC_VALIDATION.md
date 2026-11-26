# N=21 MCMC validation and L=150 timing

The pulled analyses, direct comparisons and updated L=150 run size are
recorded in [MCMC results and next runs](MCMC_VALIDATION_RESULTS.md).

These campaigns use the regular single-replica MCMC executable, θ=0,
four microcanonical sweeps per cycle, normalization every cycle, and 50
cooling sweeps with recorded cooling levels 0, 5, …, 50. The analysis uses
the cooled geometric charge `Q_U` at sweep 25, matching the near-source NS
analysis. Each simulation requests four independent single-core chains,
all with hot starts (`start 1`) to match the NS prior initialization.

| Mode | L | β | Starts | Default cycles per chain | Measure every |
| --- | ---: | ---: | --- | ---: | ---: |
| `L72-b061` | 72 | 0.61 | Four hot | 200,000 | 10 cycles |
| `L72-b060` | 72 | 0.60 | Four hot | 200,000 | 1 cycle |
| `L150-timing` | 150 | 0.60 | Four hot | 2,000 | 1 cycle |
| `L150-prior` | 150 | 0.60 | Four hot | 200,000 | 1 cycle |

The β=0.61 reference samples the same finite-volume ensemble as the
near-source reweighting target. Compare its blocked estimates of energy,
ξ², mean charge and `Vχ_t` to the two NS arms. A hot-start-only
reference relies on agreement across independent chains after burn-in and
on demonstrated charge-sector changes.

## Submit on UBELIX

Sync the updated `N21_L72_ubelix_benchmark/` scripts and the existing
`utils/cpn_io.py` and `utils/mcmc.py`. From the UBELIX checkout:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N21_L72_ubelix_benchmark/build_N21_ubelix.sh mcmc
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L72-b061
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L72-b060 200000
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L150-timing
```

The helper builds `cpn_N21` in an isolated temporary build and verifies its
compile-time N. The driver snapshots the executable and analyzer and prints
simulation and analysis job IDs, the exact `sacct` command and the results
path. Each analysis depends on successful completion of its four-chain job.
The simulation data stay on scratch. The worktree output
`N21_benchmark_results/mcmc_<mode>_<analysis_id>/` holds aggregate CSVs and
a JSON run summary, with a `completed` marker after analysis succeeds.

The 200,000-cycle L=72 source follow-up requests eight hours. The previous
20,000-cycle pilot projects to 6 h 49 min at the longer length based on
its median cycle time. The existing `cpn_N21` from the pilot can be reused.

The L=150 timing result projects 33 h 27 min for 200,000 cycles on
similar hardware, including sampling, cooling, measurements and
checkpoint I/O. The L=150 prior job requests 40 hours. The optional
last argument sets cycles per chain, and `MCMC_WALLTIME` overrides
the wall request. Submit the long L=150 prior run with

```bash
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L150-prior 200000
```

## Reported UBELIX submissions

The submission output confirms the following job IDs. Each analysis depends
on the corresponding simulation succeeding.

| Campaign | Simulation | Analysis | Scratch campaign directory | Results in the UBELIX worktree |
| --- | ---: | ---: | --- | --- |
| L=72, β=0.61 reference | 23502100 | 23502101 | `mcmc_N21_L72-b061.xYCkgitk` | `N21_benchmark_results/mcmc_L72-b061_23502101/` |
| L=72, β=0.60 prior pilot, 20,000 cycles/chain | 23502107 | 23502108 | `mcmc_N21_L72-b060.Vuwu0jlf` | `N21_benchmark_results/mcmc_L72-b060_23502108/` |
| L=150, β=0.60 timing | 23502110 | 23502111 | `mcmc_N21_L150-timing.zScGqbOz` | `N21_benchmark_results/mcmc_L150-timing_23502111/` |
| L=72, β=0.60 prior, 200,000 cycles/chain | 23568475 | 23568476 | `mcmc_N21_L72-b060.xHZHT8uu` | `N21_benchmark_results/mcmc_L72-b060_23568476/` |
| L=150, β=0.60 prior, 200,000 cycles/chain | 23568479 | 23568480 | `mcmc_N21_L150-prior.jXGFHcAW` | `N21_benchmark_results/mcmc_L150-prior_23568480/` |

The scratch campaign directories are under
`/scratch/network/users/lb25v444/out_data/`. Simulation chains are under
`job_<simulation_ID>/run_0/` through `run_3/` inside each campaign.
The worktree paths are relative to
`/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo/`.

```bash
sacct -j 23502100,23502101,23502107,23502108,23502110,23502111 \
  --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS
sacct -j 23568475,23568476,23568479,23568480 \
  --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS
```

## Review before choosing the NS prior

- Use `binning.csv` to compare chain and pooled estimates across burn-in
  cuts and block lengths. Compare the four independently seeded hot chains
  and their stability as the burn-in cut increases.
- Inspect `charge_sectors.csv` and `autocorrelation.csv` for energy,
  (G_0), (G_k), (Q_U), and (Q_U^2). The windowed integrated
  autocorrelation time is in MC cycles with the convention
  `tau_int = 1/2 + sum rho`. Constant series and unresolved windows are
  flagged. Judge estimated times alongside sector transitions and block
  stability at both of the later burn-in cuts.
- `live_spacing_windows.csv` compares the 50 points at cycles 21, 29, …,
  413 with a later 50-point window at the same spacing. For the
  200,000-cycle prior runs, the late window starts after a cut of
  20,000 cycles. The file also records non-overlapping 50-point windows
  after that cut at spacings of 512, 1,024 and 2,048 cycles. The labels
  `late_s<spacing>_<index>` identify those windows.
- For both 200,000-cycle prior runs, `autocorrelation.csv` reports
  autocorrelation times after discarding 10,000 and 20,000 cycles and
  extends the reported ACF through lag 16,384. Use the ACF and block-error
  stability to check whether the longest charge timescales are resolved
  before choosing the new live-point spacing.

Review agreement across starts, the blocking errors and the charge
autocorrelation before preparing L=150 NS runs.
