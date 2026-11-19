# L90 review through 140k NS updates

Reviewed both copied analyses, each with a `completed` marker:

- `screen_ns22635195_mc22635137_analysis_22779028/`: original four-stream
  NS job **22635195**, through 80k updates per stream.
- `screen_ns22779059_mc22635137_analysis_22803861/`: continuation job
  **22779059**, through **140k cumulative updates** per stream, with
  prefixes at 40k, 80k, 100k and 120k plus the deepest shared 140k.

Both use the same three-chain MCMC reference **22635137**, beta=0.95.
The copied MCMC CSVs and inspected histories/binning PNGs are byte-identical
between the two analysis directories. This review uses saved CSVs and
visually inspected MCMC plots. Raw simulation measurements, checkpoints,
NS acceptance histories and remote Slurm states were not inspected, and
no bootstrap was rerun locally.

## Current depth conclusion

**140k passes the observed depth-stability and edge-mass screens at the
matched target beta=0.95.** The 120k and 140k results already agree to
saved numerical precision. These are four independently seeded streams;
the continuation does not add independent streams.

| Target beta | q99 points per stream at 140k | Final-tenth mass at 140k | Depth assessment |
| --- | ---: | ---: | --- |
| 0.90 | 74,231.25 | 3.12e-92 | Stable from 100k; passes observed screens |
| 0.95 | 106,421 | 1.18e-19 | Stable from 120k; passes observed screens |
| 1.00 | 136,172.5 | 78.4% | Still truncated at 140k |

At beta=0.95 the final-tenth mass falls from approximately 100% at 80k
and 99.936% at 100k to 0.245% at 120k and 1.18e-19 at 140k. The mean
action density is 0.5779735 at 100k and 0.57485164 at both 120k and 140k.
The 95th-percentile paired bootstrap shifts between 120k and 140k are
approximately 7.0e-13 in action density, 5.3e-10 in xi_L_squared and
2.1e-15 in susceptibility: far smaller than their statistical errors.
These cover observed prefix truncation; no production error budget has
been specified independently of the current screening uncertainties.

The common low-energy edge at 140k is epsilon=0.53163907, below the
MCMC target band. Available beta=0.95 weight is shared across the four
streams (stream-weight ESS=3.9993, maximum stream mass=25.53%).
Quadrature ESS is approximately 37,364, not an independent-sample count.
The missing-target-fraction bound remains uninformative
(`log_missing_target_fraction_bound=0`). Prefix agreement and small
observed edge mass therefore do not prove absence of unseen contributions
or constrained-sampling bias. Initialization and proposal-count checks
remain outstanding.

## Matched comparison at beta=0.95

Compare the 140k NS row to MCMC with a 20,000-step cut and blocks of 128
measurements. NS errors are whole-stream bootstrap standard deviations;
MCMC errors are binned jackknife standard errors. The last column divides
NS minus MCMC by the quadrature sum of the two independent errors.

| Observable | NS, 140k | Direct MCMC | Difference / combined SE |
| --- | ---: | ---: | ---: |
| Mean action density | 0.574852 +/- 0.001203 | 0.5767309 +/- 0.0000063 | -1.56 |
| xi_L_squared | 67.609 +/- 10.328 | 54.897 +/- 1.556 | +1.22 |
| Topological susceptibility | 0.00081686 +/- 0.00001981 | 0.00085854 +/- 0.00000229 | -2.09 |
| G0 | 65.171 +/- 3.169 | 64.004 +/- 0.300 | +0.37 |
| Gk | 49.023 +/- 0.649 | 50.498 +/- 0.191 | -2.18 |

First-order square-root propagation gives NS xi_L=8.222 +/- 0.628 and
MCMC xi_L=7.409 +/- 0.105. The comparison above uses xi_L_squared
directly. Susceptibility and Gk show moderate offsets of roughly two
combined standard errors. These observables are correlated and the
offsets must not be counted as independent tests. With only four NS
streams, the precision of bootstrap error estimates is limited; these
data do not establish a bias. Extending depth from 120k to 140k has no
observed effect at beta=0.95, so the offsets are not explained by the
observed prefix truncation.

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

The follow-up setup now targets **210k in all twelve streams** to cover
the requested beta=1.0 extension as well as additional beta=0.95 statistics.
See [EXTEND_210K_12_STREAMS.md](EXTEND_210K_12_STREAMS.md) for the prepared
70k continuation, eight fresh 210k streams and dependent combined analysis.

For the matched beta=0.95 study, retain 140k as the screening depth and
prioritize eight additional independently seeded streams at the same
settings, bringing the total to twelve. At the early pilot rate a fresh
140k stream projects to about 3.62 hours, excluding initialization; this
is a projection rather than a measured deep-run time. Validate longer
initialization/live-point spacing and increased constrained proposals as
separate ensembles, and inspect NS acceptance/topology near the target
band. Settings changes must remain separate in analysis.

A common-bin correlator comparison with the existing MCMC reference can
now be attempted at beta=0.95 and 140k, using the raw UBELIX inputs.
Those raw inputs are not present in this local analysis-only copy.
Monitor the susceptibility and Gk offsets with additional seeds and
mixing checks before treating the comparison as settled.

If coverage through beta=1.0 at L90 is also required, continue the four
current streams toward 180k-210k and repeat the depth scan. The 78.4%
edge mass at 140k requires a further extension for that target. This
extension serves the beta=1.0 coverage goal, whereas beta=0.95 already
passes the observed depth screens. The MCMC reference can be reused for
beta=0.95 comparisons.
