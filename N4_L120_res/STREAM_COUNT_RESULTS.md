# L120 stream-count results, reviewed 2026-11-25

The pulled report **23463729** is complete under
`stream_count24.9OJpLn/report_23463729/`. It collects preparation **23463724**
and evaluation array **23463726**, covering old12/new12/full24 controls and
eight nested random subset orderings at 6/8/12/16/20 streams. All streams
remain at 300k updates, source beta=0.7, target beta=1.0, N=4, L120, with
50 live points per stream. MCMC reference 22780263 is unchanged.

Increasing the number of streams gives the expected precision improvement,
but does not remove the highlighted conditional G0 discrepancy. The old and
new twelve-stream cohorts reproduce essentially the same local offset.
The pooled full24 joint max-residual diagnostic is approximately **p=0.002**
under the implemented bootstrap error model.

## Integrity and scope

Verified cache/report completion markers, all nine evaluation-task markers,
task signatures and selected stream IDs, and **43 completed ensemble results**.
Recomputed the saved subset tables, scaling summaries, conditional summaries
and old/new differences from the per-subset results. There are **246 subset
observable rows** and **2,624 subset-bin rows**, including full24 once only.
Each proper stream count has eight subsets; full24 has one. All binary cache
hashes and eight analysis source hashes match their recorded values.

The copied cache JSON uses Windows CRLF line endings. Its decoded metadata
matches the report's embedded settings exactly; normalizing CRLF to LF
recovers the recorded cache metadata SHA256. This is a text-transfer change,
not a change in measurements or numerical settings. The local review did
not modify the copied cache. All three control covariance matrices are
symmetric and positive semidefinite, their diagonals match squared residual
errors, and recomputed maximum standardized residuals match `joint.json`.
The error, estimate and highlighted-bin plots were inspected. Current remote
Slurm state and original simulation text were not independently queried.

The comparison fixes the full24 common energy cutoff and MCMC-derived action
edges, uses a 20,000-MC-step cut, 32 bins, blocks of 512 measurements,
200 whole-stream bootstrap replicates per ensemble and 1,000 joint draws
for each control. Every subset/bootstrap draw is re-merged and reweighted
with its actual live-point count. No individual dead points are bootstrapped.

## Impact on statistical precision

The twelve-stream column below is the **median SE across the eight random
twelve-stream subsets**, not the error of the original twelve alone.

| Observable | Median SE at k=12 | SE at k=24 | Ratio 24/12 |
| --- | ---: | ---: | ---: |
| Action density | 0.00034786 | 0.00024885 | 0.715 |
| xi_L_squared | 14.2247 | 9.7442 | 0.685 |
| Susceptibility | 0.000012816 | 0.000008869 | 0.692 |
| G0 | 2.7079 | 1.8081 | 0.668 |
| Gk | 1.1323 | 0.8486 | 0.749 |

The 25-33% error reduction is close to the ideal factor **1/sqrt(2)=0.707**.
Across k=6-20, median SE divided by the full24-anchored 1/sqrt(k) reference
ranges from 0.988-1.118 for action, 0.962-1.032 for xi_L_squared,
0.830-1.022 for susceptibility, 0.926-1.059 for G0 and 0.925-1.021 for Gk.
There is no obvious statistical-error floor in this tested range. These
are descriptive comparisons with a reference curve, not independent fits
or a test that excludes systematic bias.

The xi_L_squared subset median changes from 64.75 at k=6 to 77.70 at k=8,
then 83.20/83.25/85.09 at k=12/16/20, versus 83.22 for full24. Small subsets
show considerable variation. The larger-count medians are close to the
pooled estimate, but they are conditioned on the same finite pool of 24
streams and do not constitute independent convergence evidence.

Subset-to-subset scatter is separate from bootstrap precision. Its value
is mechanically zero at k=24 because only one full dataset exists; the
full24 bootstrap errors remain nonzero. Shaded 10-90% subset ranges in the
plots are descriptive ranges, not confidence intervals. Overlapping subsets
and counts are correlated and cannot be treated as independent experiments.

Sources: [scaling summary](stream_count24.9OJpLn/report_23463729/scaling_summary.csv),
[error scaling](stream_count24.9OJpLn/report_23463729/error_scaling.png),
[estimate scaling](stream_count24.9OJpLn/report_23463729/estimate_scaling.png).

## Original twelve versus added twelve

The disjoint old/new cohorts agree within **1.29 combined NS SE** for every
integrated quantity examined:

| Observable | Old12 | New12 | Old-new / combined NS SE |
| --- | --- | --- | ---: |
| Action density | 0.5419042 +/- 0.0004709 | 0.5421022 +/- 0.0002124 | -0.38 |
| xi_L_squared | 89.30 +/- 12.24 | 77.44 +/- 15.83 | +0.59 |
| Susceptibility | 0.00052919 +/- 0.00001383 | 0.00050925 +/- 0.00001063 | +1.14 |
| G0 | 104.8416 +/- 2.4230 | 100.0531 +/- 2.8256 | +1.29 |
| Gk | 84.2260 +/- 1.1491 | 82.5347 +/- 1.1219 | +1.05 |

The log_Z_ratio difference is -0.35 combined NS SE. MCMC cancels from this
old-minus-new comparison; its error is not added twice. The largest
old/new conditional-bin difference is 2.19 SE (Gk bin22), before accounting
for searching the bins. There is no isolated cohort discrepancy established
by these tables, and no basis here for excluding one cohort.

Source: [old/new differences](stream_count24.9OJpLn/report_23463729/old_new_differences.csv).

## Persistent conditional G0 offset

In the preselected action bin9, epsilon approximately
**0.540418465-0.540642218**, the NS-minus-MCMC residuals are:

| Ensemble | G0 residual +/- marginal SE | Largest marginal absolute residual / SE | Approximate joint p |
| --- | --- | ---: | ---: |
| Old12 | -24.7677 +/- 7.8964 | 3.137 | 0.06194 |
| New12 | -25.9543 +/- 8.7721 | 2.959 | 0.09091 |
| Full24 | -25.4450 +/- 6.0014 | 4.240 | 0.001998 |

This same bin is the maximum standardized residual in all three controls.
The old/new conditional means differ by only **1.1866 +/- 11.0609**, or
0.11 combined NS SE. Pooling increases precision around a similar offset;
it is not creating an offset unique to the new cohort.

The highlighted residual is **negative in all 40 proper subsets**. At k=20
the eight residuals range from -27.047 to -22.446; full24 gives -25.445.
At k=6/8 the ranges are broader, extending roughly from -38 to -7. These
subsets overlap, so forty negative entries are not forty independent tests.

The full24 joint diagnostic accounts for selecting the largest residual
over both correlators and all 32 bins in this fixed configuration. Its
simultaneous 95% critical value is **3.310**, versus the observed **4.240**.
Thus this error model flags the pooled comparison at 5%. Each twelve-stream
control separately remains above p=0.05. The p about 0.002 is an approximate
centered-bootstrap result with only 200 NS bootstrap replicas and 1,000 joint
draws, conditional on fixed estimated edges and adequate MCMC blocking.
It is not a precise tail probability or proof that the NS sampler alone
is biased. Shared MCMC limitations and error-model inadequacy also remain
possible explanations.

The integrated full24 comparisons remain within 1.69 combined SE of MCMC,
with unchanged central values. The earlier production review's 4.42-SE
marginal G0 residual becomes 4.24 here because the 200-draw bootstrap seed
changes the estimated error; the central residual stays -25.445.

Sources: [highlighted-bin plot](stream_count24.9OJpLn/report_23463729/focus_G0_scaling.png)
and `evaluations/task_0/{old12,new12,full24}/comparison/joint.json` and
`bins.csv` in the same campaign.

## Consequence

More streams are useful for precision, and the observed errors broadly
follow the expected scaling. They are not washing out the conditional G0
feature. Retain the full24 production estimate and both disjoint controls;
prioritize source-beta thermalization/live-point-spacing checks, constrained-
mixing validation and target-MCMC/error-model diagnostics before increasing
the stream count further solely to resolve this discrepancy. No additional
production depth is indicated by the previous 270k-to-300k checks.
