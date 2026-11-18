# Findings from the local three-volume comparison

## Matching the supplied table

The matching-volume NS estimates agree with the supplied table:

| beta | L | NS xi_L | Table xi_L | Difference / combined statistical SE |
| --- | ---: | ---: | ---: | ---: |
| 0.70 | 22 | 1.907 ± 0.307 | 1.7842 ± 0.0059 | +0.40 |
| 0.80 | 38 | 2.975 ± 0.111 | 3.039 ± 0.012 | -0.58 |
| 0.90 | 66 | 5.547 ± 0.247 | 5.398 ± 0.022 | +0.60 |

The L66 MCMC value 5.465 ± 0.072 also agrees with the L66 table point
(+0.88 combined SE). L22 here is the locally available 25-stream subset,
not the more precise 800-stream production estimate. All square-root
errors in this comparison use first-order propagation from xi_L_squared.

## Common beta comparisons

At beta=0.9, L38 and L66 are consistent:

| Observable | L38 NS | L66 NS | L66 minus L38 / combined SE |
| --- | ---: | ---: | ---: |
| Action density | 0.617004 ± 0.000640 | 0.617279 ± 0.000601 | +0.31 |
| xi_L | 5.480 ± 0.094 | 5.547 ± 0.247 | +0.25 |
| chi_topological | 0.00134846 ± 0.00001927 | 0.00136015 ± 0.00001860 | +0.44 |

At beta=1.0, topology changes substantially with volume even though action
and xi_L are statistically consistent between L38 and L66:

| Observable | L38 NS | L66 NS | L66 minus L38 / combined SE |
| --- | ---: | ---: | ---: |
| Action density | 0.540828 ± 0.000704 | 0.541976 ± 0.000871 | +1.02 |
| xi_L | 10.274 ± 0.150 | 10.309 ± 0.316 | +0.10 |
| chi_topological | 0.00036893 ± 0.00001457 | 0.00051071 ± 0.00001161 | +7.61 |

The ratio L/xi_L at beta=1.0 is approximately 2.59, 3.70 and 6.40 for
L22, L38 and L66 respectively. Their susceptibilities are approximately
0.0001029, 0.0003689 and 0.0005107. This strong trend is consistent with
finite-volume sensitivity of topology; the volume comparison alone cannot
separate that explanation from possible sampling biases, since proposal
counts and stream ensembles differ. The planned same-volume L66 MCMC check
at beta=1.0 would directly test the highest-beta reweighted NS result.

In particular, agreement of xi_L across L38 and L66 at beta=1.0 does not
establish that chi_topological is volume independent. The table's beta=1.0
reference uses L120, not L66.

## Availability and limitations

- L22: 25 streams, 50k updates, 1,500 proposals/update. Reweighted locally
  at all seven betas with 200 whole-stream bootstrap replicates.
- L38: 24 streams, 35k updates, 8,664 proposals/update. Saved summaries
  exist locally only at beta=0.8, 0.9 and 1.0. The missing four betas
  remain gaps; they were not interpolated or replaced with other ensembles.
- L66: 12 streams, 110k updates, 26,136 proposals/update, all seven betas.
  Negative xi_L_squared central values at beta=0.7 and 0.75 are preserved
  and marked unresolved; no real central xi_L is plotted there.
- MCMC: saved L38 beta=1.0 and L66 beta=0.9 references only. No L22
  production MCMC data are available locally.
- Observed final-edge weights pass the 1% screen for every available
  point. This screen and statistical errors do not establish absence of
  constrained-chain mixing bias or unseen target weight.

The six-panel figure, matching-table figure, coverage diagnostics, numeric
tables, exact input hashes and reproduction commands are in this directory.
The L22 input list and full bootstrap settings are in `L22/inputs.json`.
