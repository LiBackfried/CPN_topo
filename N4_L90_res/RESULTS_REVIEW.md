# L90 results through 210k NS updates

The latest copied analysis, with a `completed` marker, is
`combined210_ns22810844_analysis_22810847/`: **twelve independent streams,
210k updates each**, from NS jobs 22810844, 22810845 and 22810846. Its
depth scan contains 100k, 120k, 140k, 160k, 180k, 200k and 210k prefixes.
The earlier completed four-stream analyses remain available:

- `screen_ns22635195_mc22635137_analysis_22779028/`: original four-stream
  NS job **22635195**, through 80k updates per stream.
- `screen_ns22779059_mc22635137_analysis_22803861/`: continuation job
  **22779059**, through **140k cumulative updates** per stream, with
  prefixes at 40k, 80k, 100k and 120k plus the deepest shared 140k.

All use the same three-chain MCMC reference **22635137**, beta=0.95.
The latest cut MCMC CSV and histories/binning PNGs are byte-identical to
the previous 140k copy. This review uses saved CSVs, the correlator-bin
plot and the previously inspected MCMC plots; raw measurements and NS
acceptance histories are not included in these local analysis copies.

## Current depth conclusion

**210k passes the observed depth-stability and edge-mass screens through
beta=1.0.** In the twelve-stream scan, the first tested prefixes that pass
both screens are 100k at beta=0.9, 120k at beta=0.95 and 160k at beta=1.0.
Further depth beyond 210k is not indicated by these diagnostics.

| Target beta | q99 points per stream at 210k | Final-tenth mass at 210k | First tested prefix passing both screens |
| --- | ---: | ---: | --- |
| 0.90 | 73,954.33 | 2.04e-318 | 100k |
| 0.95 | 105,214.92 | 2.06e-166 | 120k |
| 1.00 | 137,174.5 | 2.19e-68 | 160k |

At beta=0.95 the twelve-stream final-tenth mass falls from 99.958% at
100k to 0.102% at 120k, 3.19e-20 at 140k and 2.06e-166 at 210k. The
120k and 210k means agree to numerical precision. Their 95th-percentile
paired bootstrap shifts are 8.64e-13 in action density, 1.22e-10 in
xi_L_squared and 1.36e-15 in susceptibility.

At beta=1.0, 140k has 94.5% of its weight in the final tenth, but its
observable shifts relative to 210k are already small: the paired 95th
percentiles are at most about 5% of the respective statistical errors.
Thus a large final-tenth mass alone does not demonstrate a large
truncation bias. At 160k the edge mass is 6.86e-6 and all reported means
and paired shifts match 210k to saved numerical precision. This is the
first tested depth passing the conservative edge screen as well.

The common low-energy edge at 210k is epsilon=0.47321203. Available
beta=0.95 weight is shared across twelve streams (stream-weight
ESS=11.9977, maximum stream mass=8.49%). Quadrature ESS is approximately
115,461, not an independent-sample count.
The missing-target-fraction bound remains uninformative
(`log_missing_target_fraction_bound=0`). Prefix agreement and small
observed edge mass therefore do not prove absence of unseen contributions
or constrained-sampling bias. Initialization and proposal-count checks
remain outstanding.

## Matched comparison at beta=0.95

Compare the twelve-stream 210k NS row to MCMC with a 20,000-step cut and blocks of 128
measurements. NS errors are whole-stream bootstrap standard deviations;
MCMC errors are binned jackknife standard errors. The last column divides
NS minus MCMC by the quadrature sum of the two independent errors.

| Observable | NS, twelve streams at 210k | Direct MCMC | Difference / combined SE |
| --- | ---: | ---: | ---: |
| Mean action density | 0.576610 +/- 0.000663 | 0.5767309 +/- 0.0000063 | -0.18 |
| xi_L_squared | 51.632 +/- 5.563 | 54.897 +/- 1.556 | -0.57 |
| Topological susceptibility | 0.00086580 +/- 0.00001983 | 0.00085854 +/- 0.00000229 | +0.36 |
| G0 | 63.630 +/- 1.653 | 64.004 +/- 0.300 | -0.22 |
| Gk | 50.841 +/- 0.796 | 50.498 +/- 0.191 | +0.42 |

First-order square-root propagation gives NS xi_L=7.186 +/- 0.387 and
MCMC xi_L=7.409 +/- 0.105. The comparison above uses xi_L_squared
directly. All five integrated observables agree within 0.6 combined
standard errors. The previous four-stream susceptibility and Gk offsets
of about two SE are absent in these integrated results. Susceptibility
uncertainty remains about 2.0e-5 despite adding streams; uncertainty
depends on the newly observed stream scatter and need not decrease by
the nominal square-root stream-count factor. Old and expanded estimates
share four streams, so they are not independent.

## Conditional correlator bin differences

The 32-bin common-range comparison covers 98.92% of NS mass and 99.00%
of MCMC mass. Integrated G0 and Gk agree as above, and the action
histograms visually overlap, but some conditional Gk means differ
substantially:

| Action-density interval | NS minus MCMC in Gk | Reported SE | Difference / SE |
| --- | ---: | ---: | ---: |
| 0.57593056 to 0.57619633 | +12.363 | 2.589 | +4.77 |
| 0.57837112 to 0.57867109 | -9.602 | 3.114 | -3.08 |

Four of the 32 Gk bins exceed two reported SE and two exceed three;
no G0 bin exceeds two (maximum 1.83). Positive and negative Gk
differences cancel in the integrated mean. These bins are correlated,
and the stored marginal errors do not supply a global test statistic
or a global significance after selecting the largest bin. The local
differences nevertheless merit follow-up before claiming complete
conditional-sampling validation.

Repeat the raw-data comparison with fewer bins, for example 8 and 16,
and larger MCMC blocks, for example 512 or 1,024 measurements. Assess
bin covariance from joint resamples rather than summing marginal
residual squares. Investigate NS acceptance/mixing near the target band,
and compare independently seeded ensembles with increased proposals
(for example 97,200=12L^2) and longer source initialization/live-point
spacing. Keep those settings separate. The current summaries do not
identify the cause of the conditional Gk differences.

## NS depth: 80k fails the target-coverage screen

| Target beta | q99 points per stream | Weight in the final tenth of common ranks at 80k |
| --- | ---: | ---: |
| 0.90 | 74,231 | 5.93% |
| 0.95 | 79,873.5 | Approximately 100% |
| 1.00 | 79,875.5 | Approximately 100% |

All three fail the initial 1% edge-mass screen. At beta=0.95 and 1.0 the
target mass is pinned to the truncation edge, so q99 is itself truncated
and does not estimate the depth needed for full coverage. The 20k, 40k
and 60k beta=0.95 rows likewise place approximately all weight in the
final tenth. At beta=0.95 the estimated mean action density changes from
0.721260 to 0.670130 to 0.632269 to 0.601826 as the prefix deepens.
There is no depth plateau in these data.

The common low-energy edge at 80k is epsilon=0.60138076. Direct beta=0.95
MCMC has mean epsilon=0.57673092, below the entire available common NS
energy range. This supports the truncation diagnosis independently of
the edge-mass statistic.

The beta=0.95 NS estimate is epsilon=0.60182557 with a whole-stream
bootstrap standard error of 0.00001548. This small error describes
resampling the available, truncated streams; it does not include the
missing-target-mass bias. It cannot be used for a formal canonical
comparison. The corresponding truncated xi_L_squared=39.497(22.211)
and chi_topological=0.00112792(0.00003347) are not validated physical
target estimates either.

Stream-weight ESS is approximately 4, and the maximum stream weight is
about 25.3% at beta=0.95. Thus the available weight is shared across all
four streams, but that does not establish target coverage or constrained
mixing. Quadrature ESS is approximately 2,592 and is not a number of
independent samples. `log_missing_target_fraction_bound=0` at all three
targets: the reported bound is uninformative. Values of the edge mass
slightly above one at floating-point round-off are interpreted as 100%.

## MCMC reference: useful preliminary diagnostics

Using the 20,000-MC-step cut and blocks of 128 measurements (1,280 MC
steps), the pooled saved results are:

| Observable | Estimate | Binned jackknife standard error |
| --- | ---: | ---: |
| Mean action density | 0.576730924 | 0.000006314 |
| xi_L_squared | 54.8974 | 1.5562 |
| Topological susceptibility | 0.000858542 | 0.000002289 |
| Mean geometric Q_U | 0.001069 | 0.004909 |

Each chain retains 98,000 measurements before complete-block truncation;
the chosen block analysis uses 97,920 per chain, 293,760 total.
First-order propagation through the square root gives
**xi_L=7.4093 +/- 0.1050**. The user's transcribed matching L90,
beta=0.95 row is xi_L=7.314 +/- 0.033: the difference is about 0.87
combined standard errors. This square-root error is propagated from
xi_L_squared, not a new bootstrap of xi_L.

The individual-chain xi_L_squared results at that block size are
57.24 +/- 2.80, 55.49 +/- 2.70 and 52.01 +/- 2.59. The largest pairwise
action-mean difference is approximately 2.3 combined standard errors;
there is no strong chain discrepancy in xi_L_squared or topology.

Visually inspected histories show no obvious persistent action drift and
frequent changes of cooled topological sector: 87,190, 87,214 and 87,321
after the cut. These checks do not prove equilibration of every slow mode.
The cut changes the pooled xi_L_squared from 54.710 to 54.897, small
relative to its quoted standard error; the action and topology shifts
are also small on that scale. Full/cut estimates share data and are not
independent measurements.

Over blocks of 64-2,048 measurements, pooled action errors stay around
6.15e-6 to 6.31e-6, and xi_L_squared errors range from 1.47 to 1.59.
The topological-susceptibility error increases from 2.26e-6 to 2.45e-6,
about 8%. Thus the binning is broadly reassuring, with a modest residual
bin-size dependence for topology. Use a more conservative large-bin
topology error, or establish its plateau more firmly, for final precision.

## Next steps

Keep the completed 210k ensemble and focus L90 follow-up on the conditional
Gk differences and mixing checks. More NS depth is not indicated by the
current coverage/stability diagnostics. The beta=1.0 L90 result has no
matching-volume direct MCMC reference in this campaign; the L120
beta=1.0 reference is a different volume. For L120, the copied 120k
NS screen remains strongly truncated; see
[the L120 review](../N4_L120_res/RESULTS_REVIEW.md).
