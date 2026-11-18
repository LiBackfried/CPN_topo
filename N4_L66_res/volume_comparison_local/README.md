# Local L22/L38/L66 comparison

This comparison uses 25 local L22 streams (runs 750–774), the saved 24-stream L38 ensemble at 8,664 proposals/update, and 12 L66 streams at 26,136 proposals/update. L22 uses 1,500 proposals/update. All simulations have N=4, source beta=0.7 and theta=0.

The L22 grid was regenerated locally with 200 whole-stream bootstrap replicates, seed 20261118. It is a subset, not the 100-stream UBELIX scan or the 800-stream production estimate. Its exact inputs and settings are in L22/inputs.json and L22/selected_runs.txt.

L38 summaries are available only at beta=0.8, 0.9 and 1.0. The four other L38 betas are missing and remain gaps; no interpolation was performed. L66 covers all seven betas from 0.7 to 1.0.

Direct MCMC references are included only at their simulated points: L38 at beta=1.0 (job 22121710) and L66 at beta=0.9 (job 22587511). Both use the saved pooled jackknife with a 20,000-MC-step burn-in cut and blocks of 128 measurements. No L22 production MCMC reference is available locally.

All xi and xi/L errors use first-order propagation of xi-squared errors, for consistency with saved depth summaries that lack raw xi bootstrap samples. Negative xi-squared estimates are preserved. Their square roots and propagated errors remain NaN, and question marks flag the unresolved L66 points in the xi/L panel. This propagation is not a bootstrap interval for xi.

## Outputs

- volume_dependence.png and .pdf: six observable panels. NS is crimson; MCMC is royalblue. Markers distinguish volumes.
- coverage_diagnostics.png: edge weight, stream-weight ESS and quadrature ESS (not independent sample counts).
- matched_table_comparison.png and .pdf: only matching-volume, matching-beta checks against the supplied Table III.
- volume_comparison.csv: all available estimates, errors and provenance.
- volume_shifts.csv: larger minus smaller volume at common available betas, with independent-volume errors added in quadrature.
- ns_mcmc_comparison.csv: same-volume, same-beta NS/MCMC checks.
- matched_table_checks.csv: table comparisons with combined errors.
- availability.csv: all 21 volume/beta combinations, including gaps.
- provenance.json: exact source paths, SHA256 hashes and methods.

Errors are statistical. Different proposal counts and initialization or constrained-chain mixing biases can affect comparisons; a volume shift alone does not establish its physical origin. Edge weight below 1% is a screen, not proof of complete target coverage. A bound of zero in log_missing_target_fraction_bound is uninformative.

## Reproduce from the repository root

Use the fpaction2 Conda environment locally. To rebuild the L22 scan:

```bash
python N4_volume_benchmark/scan_volume_betas.py ../data_N4_UBELIX --output N4_L66_res/volume_comparison_local/L22 --bootstrap 200 --seed 20261118 --expected-lattice 22 --expected-stoc 1500 --expected-chains 25
```

To regenerate comparison tables and figures from saved summaries:

```bash
python N4_volume_benchmark/compare_saved_volumes.py
```
