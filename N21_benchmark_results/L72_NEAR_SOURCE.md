# N=21 L=72 statistics at β=0.60 and reweighting to β=0.61

Add ten independent streams per proposal count at β=0.60, θ=0, with 50 live
points and 20,000 NS updates per stream. The new streams use the original
campaign's checked executable and keep the initialization, normalization and
measurement settings fixed. The original 5,000-update ten-stream ensembles
are jobs 23350970 (15,500 proposals) and 23350971 (31,000 proposals).

| What to measure | Controlled comparison |
| --- | --- |
| Gain from more independent statistics | Original 10 streams, new 10 streams and pooled 20 streams at the same 5,000-update depth, separately for each proposal count |
| Depth needed for reweighting | Prefixes of the same new streams at 500, 1,000, 2,000, 5,000, 10,000 and 20,000 NS updates, using paired stream bootstrap draws |
| Sensitivity to constrained updates between measurements | Compare 15,500 with 31,000 proposals per NS update at the same prefix lengths and target β |

An NS update retires one measured dead point. Within it, the proposal count
controls the constrained heatbath work after four microcanonical sweeps.
`meas_every=8` controls the spacing of the **initial live points** along
their thermalizing chain. It stays fixed here, along with the initial 20
sweeps, so a change in initialization does not confound the proposal-count
comparison. Check initialization separately against autocorrelation and
thermalization in direct MCMC.

At β=0.60 the original 5,000-update run already had negligible expected
remaining prior mass. The added independent streams are the main lever for
its precision. The longer trajectories test the low-energy support needed
at β=0.61. The two original and two long simulations give 20 distinct
seeds per proposal count at 5,000 steps, and ten at deeper prefixes.

## UBELIX submission

Sync `N21_L72_ubelix_benchmark/submit_ubelix.sh`,
`N21_L72_ubelix_benchmark/scan_targets_ubelix.sh` and
`N4_volume_benchmark/scan_depth.py` to the repository on UBELIX. Run:

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N21_L72_ubelix_benchmark/submit_ubelix.sh near-source
```

The driver reads the original campaign
`/scratch/network/users/lb25v444/out_data/ns_N21_L72_benchmark.5NegZsTv`.
It submits two ten-task fresh runs and an analysis job that depends on both.
The new seed ranges are 21722001–21722010 and 21722101–21722110. Use a
different `NS_SEED_BASE` for a later independent repetition. The two-hour
simulation request allows for median loop-time estimates of about 60 and
77 minutes per stream based on the observed 5,000-step rates. Behavior
at later cutoffs can change the runtime.

The driver prints the new scratch campaign, analysis ID and results path.
The output is in `N21_benchmark_results/near_source_<analysis_ID>/` in the
UBELIX worktree. It contains `p15500_original.csv`,
`p15500_deep.csv`, `p15500_combined_5000.csv` and the corresponding
`p31000_*.csv` files. The new-depth CSVs use the same seed resamples at
every prefix. Each scan uses a common cutoff across its included streams.
The cutoff can therefore differ between the original, new and pooled
estimates at 5,000 steps. Check target weight near each cutoff when
comparing the three results. Measurements use 25 cooling sweeps.

The directory contains aggregate observables, bootstrap standard errors, depth
diagnostics and small provenance files. Simulation streams and checkpoints
remain on scratch. The scanner computes bootstrap draws in memory.

## Decide how much depth and work are needed

- At β=0.61, find the first tested depth where the 99% target-weight point
  has cleared the low-energy edge, the last tenth carries little weight,
  and the weighted energy, ξ², χ and ξ²χ stay stable as depth grows. Check
  for any one stream carrying a large fraction of target weight. Compare
  both β values to the matching L=72 local and simulated-tempering
  references in [Bonanno, Table 4.2](LITERATURE_COMPARISON.md).
- For the proposal count, compare estimates from the two arms at the same
  depth with uncertainties from independent streams. To measure constrained
  mixing itself, follow with fixed-cutoff chains at energies that carry
  significant β=0.60 or 0.61 weight. Measure autocorrelation of the
  correlators, `Q_U` and `Q_U²` against sweeps or proposals. High
  acceptance alone cannot determine the spacing needed for topology.
- For the N=4 comparison, apply the same depth scan at a nearby target
  such as β=0.70 → 0.71 on a documented N=4 ensemble. Report depth as
  updates per stream and as `−log X` at 99% target weight, using the
  retained rank divided by the total live-point count. Compare constrained
  workloads in proposals per field `n_prop / (3L²)`, with the number
  of microcanonical sweeps stated. For N=21 L=72 the two counts are about
  1.0 and 2.0 proposals per field. Use similar `L/ξ` and target overlap
  when interpreting differences. A comparison at different volumes and
  bare couplings measures the combined effect of N, physical volume and
  the reweighting shift.

The β=0.68–0.76 screen follows the near-source review. L=72 remains a
finite-volume ensemble at those couplings.
