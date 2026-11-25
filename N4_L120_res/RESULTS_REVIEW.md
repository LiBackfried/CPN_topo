# L120 results through 300k NS updates

The current **24-stream** analysis **23350708** was copied and verified
complete locally on 2026-11-25. See [the current review](RESULTS_24_STREAMS_REVIEW.md)
for the depth checks, precision gain and persistent conditional G0 offset.
The sections below retain the earlier **twelve-stream** results.

The robustness analysis **22974798**, copied on 2026-11-23, is complete.
The pooled comparison stays within joint 95% thresholds across the bin/block
grid (32-bin p about 0.085-0.093). Four-stream groups still show local
residuals; pooled agreement alone does not validate sampling. See
[the robustness review](../N4_volume_benchmark/ROBUSTNESS_REVIEW_20261123.md).

The earlier twelve-stream depth-scan analysis is
`combined300_ns22885157_analysis_22904265/`, with a `completed` marker,
**twelve independent streams and 300k updates per stream**. Its inputs
are existing NS leaf **22885157**, fresh leaves **22904262** and
**22904264**, and the three-chain beta=1.0 MCMC reference **22780263**.
The fresh leaves follow 150k starts 22904261 and 22904263. The copied
seed plan contains twelve distinct positive seeds: four existing and
eight new. The earlier four-stream 120k/240k/300k analyses remain available.

The cut MCMC CSV and histories/binning PNGs are byte-identical to the
previous four-stream 300k copy. This review uses saved CSVs, the new
conditional-bin plot and previously inspected MCMC plots; raw measurements
and NS acceptance histories are not included in the local analysis copies.

## Earlier twelve-stream depth assessment

**The twelve-stream 300k ensemble passes the observed edge and paired
prefix-stability screens through beta=1.0.** At that target, 270k and
300k means and paired shift bounds agree to saved numerical precision.
A further depth extension is not indicated by these diagnostics.

| Target beta | q99 points per stream at 300k | Final-tenth mass at 300k | First tested depth passing both screens |
| --- | ---: | ---: | --- |
| 0.90 | 130,184.08 | 2.19e-308 | 180k |
| 0.95 | 183,621.92 | 6.09e-118 | 210k |
| 1.00 | 239,531.42 | 2.99e-21 | 270k |

At beta=1.0 the final-tenth mass decreases from 99.9890% at 240k to
**0.1810% at 270k** and **2.99e-21 at 300k**. The action density changes
from 0.54198019 at 240k to 0.54190422 at 270k and remains identical at
300k. The 240k-to-300k paired 95th-percentile shifts are 0.0001505 in
action, 0.8295 in xi_L_squared and 1.574e-6 in susceptibility: approximately
32.1%, 6.9% and 11.5% of their respective 300k NS statistical errors.
All reported 270k-to-300k paired shifts are zero to saved precision.

The deeper scan shows that 240k was already close to the final means,
although it failed the conservative edge screen and its action and
susceptibility shift bounds exceed the working 10%-of-statistical-error
truncation budget in this twelve-stream ensemble.
The final-tenth statistic describes observed weight, not missing weight.
The 270k result passes both the edge and stability screens against a
distinct, deeper 300k reference. This is stronger evidence than the
mechanically zero shifts of the deepest row alone.

At 300k the common low-energy edge is epsilon=0.50552052. Beta=1.0
stream-weight ESS is 11.9992 and the maximum stream mass is 8.45%, so
available weight is shared across twelve streams. Quadrature ESS is
about 169,985 and is not an independent-sample count.
The missing-target-fraction bound remains uninformative (log bound zero).
Observed depth stability does not prove unbiased constrained sampling or
exclude every possible unseen contribution. Initialization and mixing
validation remain separate requirements.
At beta=0.9, xi_L_squared=19.40 +/- 9.27 remains noisy despite depth
stability; more depth alone does not improve this estimate.

## Matched comparison at beta 1

Use the twelve-stream 300k NS row and MCMC with a 20,000-step cut and blocks of 128
measurements. NS errors are whole-stream bootstrap standard deviations;
MCMC errors are binned jackknife standard errors. The last column uses
the quadrature sum of the two independent errors.

| Observable | NS at 300k | Direct MCMC | Difference / combined SE |
| --- | ---: | ---: | ---: |
| Mean action density | 0.541904 +/- 0.000470 | 0.5419981 +/- 0.0000043 | -0.20 |
| xi_L_squared | 89.300 +/- 12.010 | 98.764 +/- 2.949 | -0.77 |
| Topological susceptibility | 0.00052919 +/- 0.00001373 | 0.00051145 +/- 0.00000140 | +1.29 |
| G0 | 104.842 +/- 2.431 | 105.625 +/- 0.535 | -0.31 |
| Gk | 84.226 +/- 1.102 | 83.123 +/- 0.328 | +0.96 |

All five integrated estimates agree within 1.3 combined SE. First-order
square-root propagation gives NS xi_L=9.450 +/- 0.635 and MCMC
xi_L=9.938 +/- 0.148. The added streams reduce the action, xi-squared
and susceptibility errors relative to the four-stream copy. The two
ensembles share four streams, so their change in central values is not
an independent comparison. Integrated agreement and depth stability
still leave initialization and constrained-mixing checks outstanding.

## Conditional correlator bins

The new 32-bin comparison at beta=1.0 covers 98.89% of NS weight and
99.00% of MCMC weight. Its integrated G0 and Gk differences are
-0.784 +/- 2.489 and +1.103 +/- 1.150, respectively. Within-bin and
bin-weight contributions largely cancel or remain statistically modest
in the integrated comparison.

The largest marginal G0-bin residual is **-3.32 reported SE**:
epsilon=0.54041839 to 0.54064214, with NS minus MCMC
**-24.592 +/- 7.400**. Three of 32 G0 bins exceed two SE and one
exceeds three. The largest Gk-bin residual is **1.99 SE**, with no
Gk bin above two. These are correlated bins with selection over many
comparisons; the largest residual is not a global significance or proof
of a sampling bias. The G0 feature merits a robustness check, while
the stronger L90 conditional Gk features remain a separate diagnostic.

Repeat the comparison with 8/16 bins and larger MCMC blocks such as
512/1,024 measurements. Use joint resamples/covariance for any global
test rather than adding marginal residual squares. Raw inputs or joint
resamples are needed for that test; the saved marginal CSV errors alone
do not supply it.

## Initial 120k screen

At the deepest 120k prefix, approximately all available target weight
lies in the final tenth at beta=0.9, 0.95 and 1.0:

| Target beta | q99 points per stream | Final-tenth weight | Mean action density |
| --- | ---: | ---: | ---: |
| 0.90 | 119,782.5 | 99.9989% | 0.621289 |
| 0.95 | 119,797.0 | Approximately 100% | 0.619841 |
| 1.00 | 119,797.5 | Approximately 100% | 0.619769 |

At beta=1.0, mean action density drops from 0.730995 at 30k to 0.683950
at 60k, 0.648679 at 90k and 0.619769 at 120k. There is no depth plateau.
The common low-energy edge is epsilon=0.61968896, whereas direct MCMC
has mean epsilon=0.54199808, below the entire available common NS range.
This makes the beta=1.0 coverage failure unambiguous.

The 120k beta=1.0 NS susceptibility is approximately 0.00141169, far
from the direct MCMC value 0.00051145. Its xi_L_squared=308.8 +/- 260.0
is very imprecise. These are truncated estimates and cannot be interpreted
as a test of physical agreement. Stream-weight ESS near four does not
remedy the missing energy range. The log missing-target-fraction bound
is zero at all targets and is uninformative.

## MCMC reference

Using the provisional 20,000-MC-step cut and blocks of 128 measurements
(1,280 MC steps), the pooled results are:

| Observable | Estimate | Binned jackknife standard error |
| --- | ---: | ---: |
| Mean action density | 0.54199808 | 0.00000432 |
| xi_L_squared | 98.76399 | 2.94913 |
| Topological susceptibility | 0.000511450 | 0.000001403 |
| Mean geometric Q_U | 0.002437 | 0.005748 |

Each chain retains 98,000 measurements before complete-block truncation;
the block analysis uses 97,920 per chain and 293,760 total. First-order
square-root propagation gives **xi_L=9.938 +/- 0.148**, consistent with
the user's transcribed L120 beta=1.0 reference, 9.997 +/- 0.045
(difference approximately -0.38 combined SE). This is propagated
uncertainty, not a new bootstrap of xi_L.

After the cut, the individual-chain xi_L_squared estimates are
96.77 +/- 5.24, 104.60 +/- 5.10 and 94.95 +/- 4.99. The largest
susceptibility difference between two chains is approximately 2.18
combined SE. The cut changes pooled xi_L_squared from 98.707 to 98.764
and susceptibility from 0.000511654 to 0.000511450, small relative to
the quoted errors. Full/cut samples overlap and are not independent.

Histories show no obvious persistent action drift and frequent changes
of cooled topological sector: 87,141, 86,879 and 86,965 after the cut.
These observations do not prove equilibration of every slow mode.
Across blocks of 64-2,048 measurements, pooled xi_L_squared errors range
from 2.91 to 3.03 and susceptibility errors from 1.375e-6 to 1.419e-6.
This supports using the existing reference while checking its precision
against the final NS comparison.

## Next steps

Retain the twelve completed 300k streams and existing MCMC reference.
The next priority is binning/error robustness and constrained-mixing
validation; the depth diagnostics do not call for another production
extension. Inspect acceptance/topology near the target band and compare
longer source initialization/spacing and increased proposals (for example
172,800=12L^2) as separately seeded validation ensembles. Changes in
settings must remain separate in analysis. The present summaries do not
identify a cause for the isolated G0-bin residual.

The completed analysis is **22904265**, combining existing **22885157**
and fresh leaves **22904262/22904264**. Campaign details are in
[ADD_8_STREAMS_300K.md](ADD_8_STREAMS_300K.md); historical submission and
local-completion records are in
[reported_add8_jobs_20261120.tsv](reported_add8_jobs_20261120.tsv).
