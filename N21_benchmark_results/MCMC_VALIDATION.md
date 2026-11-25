# N=21 MCMC validation and L=150 timing

These campaigns use the regular single-replica MCMC executable, θ=0,
four microcanonical sweeps per cycle, normalization every cycle, and 50
cooling sweeps with recorded cooling levels 0, 5, …, 50. The analysis uses
the cooled geometric charge `Q_U` at sweep 25, matching the near-source NS
analysis. Each simulation requests four independent single-core chains,
all with hot starts (`start 1`) to match the NS prior initialization.

| Mode | L | β | Starts | Default cycles per chain | Measure every |
| --- | ---: | ---: | --- | ---: | ---: |
| `L72-b061` | 72 | 0.61 | Four hot | 200,000 | 10 cycles |
| `L72-b060` | 72 | 0.60 | Four hot | 20,000 | 1 cycle |
| `L150-timing` | 150 | 0.60 | Four hot | 2,000 | 1 cycle |
| `L150-prior` | 150 | 0.60 | Four hot | 20,000, adjustable after timing | 1 cycle |

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
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L72-b060
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L150-timing
```

The helper builds `cpn_N21` in an isolated temporary build and verifies its
compile-time N. The driver snapshots the executable and analyzer and prints
simulation and analysis job IDs, the exact `sacct` command and the results
path. Each analysis depends on successful completion of its four-chain job.
The simulation data stay on scratch. The worktree output
`N21_benchmark_results/mcmc_<mode>_<analysis_id>/` holds aggregate CSVs and
a JSON run summary, with a `completed` marker after analysis succeeds.

The L=150 timing output gives the observed process wall time per MC cycle,
including sampling, cooling, measurements and checkpoint I/O. Use the rates
and their spread to size the longer pilot. The optional last argument is the
number of cycles per chain, and `MCMC_WALLTIME` overrides the wall request.
For example, the default L=150 prior probe can be submitted explicitly with:

```bash
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L150-prior 20000
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
  413 with a later 50-point window at the same spacing after a provisional
  cut of 5,000 cycles. Compare these means along with the burn-in scan
  and the lag-eight ACF. Use the slowest resolved relevant observable
  when choosing a new live-point spacing.

Size the L=150 prior runs from the timing pilot. Review agreement across
starts, the blocking errors and the charge autocorrelation before preparing
L=150 NS runs.
