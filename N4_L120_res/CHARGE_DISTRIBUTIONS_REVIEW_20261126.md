# L120 charge distributions checked on 2026-11-26

Completed local export: `proposal_charge_distributions/job_23600131/`.
The parent and both cohort completion markers, histogram CSVs, provenance,
PNG/PDF plots and comparison plot-input hashes are present. All eight
recorded analysis-source hashes match this checkout. The selection-manifest
hash matches the local proposal-analysis `inputs.json` after normalizing
Windows CRLF line endings to LF; the raw byte-hash difference is explained
by those line endings. Both histogram CSV hashes match the plotted inputs.
Analysis revision: `31b211bf3415e18f0359124989c04ea84d94a798`.

## Settings and checks

The figures compare canonical beta=1 histograms from baseline24 (86400
proposals/update), control8 (172800), and MCMC 22780263. NS source beta is
0.7, depth is 300k updates/stream, N=4 and L=120. Charges are measured
after 50 cooling sweeps, using unit-width bins centered on integers,
without rounding the raw measurements or symmetrizing distributions.

Each cohort contains six normalized histograms: NS/MCMC for Q_U, Q_z and
Q_plaquette. Every histogram sums to one within 1.6e-12. Bin probabilities,
errors, indexing and contiguous edges pass the existing histogram validator.
The two exports give matching MCMC probabilities and errors, including
empty bins outside the smaller export's range. NS uses 200 whole-stream
bootstrap draws per cohort. MC uses burn-in 20000 steps, block size 512
measurements, 573 complete blocks, and drops 208 trailing measurements
independently from each of the three chains.

## Interpretation

The central charge distributions closely overlap visually. All three charge
definitions show a similar overall shape, and doubling proposals produces
no large change in the width. Descriptive statistics reconstructed from
the unit-width **Q_U histogram centers** are:

| Ensemble | Mean Q_U | Variance | P(abs(Q_U) >= 8) |
| --- | ---: | ---: | ---: |
| Baseline24 | 0.03145 | 7.48865 | 0.006685 |
| Control8 | 0.16442 | 7.42316 | 0.006411 |
| MCMC | 0.00222 | 7.36489 | 0.006084 |

The corresponding histogram variances divided by 120² reproduce the
susceptibilities in the proposal-comparison tables to numerical precision.
The table is descriptive: the exported bin-error diagonal alone cannot
provide uncertainty on a mean, variance or integrated tail because bin
probabilities are correlated. For the continuous plaquette estimator,
moments reconstructed from bin centers additionally have binning error.

Control8 has a small shift toward positive charge and differences in some
tails. The most pronounced selected Q_U bin is Q=-11: control probability
9.40e-6 versus MC 7.16e-5, a difference of -6.22e-5 with combined marginal
SE 1.65e-5 (3.78 SE). Several central/flank bins differ by about 2–2.5 SE.
Baseline24's largest absolute Q_U marginal residual is about 1.54 SE.
These are selected comparisons among many correlated bins; no global
charge-histogram test or mean-charge significance has been computed.
Eight control streams also limit the precision of tail errors.

The figures are reassuring about the overall marginal charge shape, but
they do not establish complete mixing or resolve the separate conditional
G0 discrepancy at fixed action. A similar marginal Q distribution can
coexist with different joint distributions of action and correlators.

## Figures

- [Q_U: linear and logarithmic views](proposal_charge_distributions/job_23600131/comparison/L120_Q_U_proposal_comparison.png)
- [Q_z](proposal_charge_distributions/job_23600131/comparison/L120_Q_z_proposal_comparison.png)
- [Q_plaquette](proposal_charge_distributions/job_23600131/comparison/L120_Q_plaquette_proposal_comparison.png)

PDF versions are alongside the PNGs. The displayed horizontal range covers
bins with any probability at least 1e-6, and the logarithmic view has a
1e-6 floor. Full normalized histograms remain in the per-cohort CSVs;
cropping does not renormalize the visible bins. Completion was checked from
the pulled artifacts; remote accounting and raw histories were not queried.
