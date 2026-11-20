# L120 results through 300k NS updates

The latest copied analysis is
`screen_ns22885157_mc22780263_analysis_22885274/`, with a `completed`
marker and **four streams through 300k cumulative NS updates each**.
Continuation job **22885157** follows 240k leaf **22860149** and initial
120k job **22780262**; continuations add no independent streams. The
completed 120k and 240k analyses remain available.

All use the same three-chain beta=1.0 MCMC reference **22780263**. The
cut MCMC CSV and histories/binning PNGs are byte-identical between the
latest two copies. All 36 checked action/xi-squared/susceptibility/log-ratio
estimates at shared 180k/210k/240k prefixes match exactly. This review
uses saved CSVs and the previously inspected MCMC plots; raw measurements
and NS acceptance histories are not included in the local analysis copies.

## Current depth assessment

**300k passes the observed edge and paired prefix-stability screens
through beta=1.0.** At that target, 270k and 300k means and paired
shift bounds agree to saved numerical precision. A further extension
to 370k is not indicated by these depth diagnostics.

| Target beta | q99 points per stream at 300k | Final-tenth mass at 300k | First tested depth passing both screens |
| --- | ---: | ---: | --- |
| 0.90 | 130,158.5 | 1.82e-309 | 180k |
| 0.95 | 183,181.75 | 6.18e-119 | 210k |
| 1.00 | 238,546 | 1.01e-21 | 270k |

At beta=1.0 the final-tenth mass decreases from 99.9696% at 240k to
**0.0669% at 270k** and **1.01e-21 at 300k**. The action density changes
from 0.54234933 at 240k to 0.54231656 at 270k and remains identical at
300k. The 240k-to-300k paired 95th-percentile shifts are 9.99e-5 in
action, 1.644 in xi_L_squared and 6.29e-7 in susceptibility: approximately
10.04%, 8.59% and 3.47% of their respective 300k NS statistical errors.
The corresponding G0/Gk shifts are 0.0903 and 0.2096. All reported
270k-to-300k paired shifts are zero to saved precision.

The deeper scan shows that 240k was already close to the final means,
although it failed the conservative edge screen and its action shift
bound was about the working 10%-of-statistical-error truncation budget.
The final-tenth statistic describes observed weight, not missing weight.
The 270k result passes both the edge and stability screens against a
distinct, deeper 300k reference. This is stronger evidence than the
mechanically zero shifts of the deepest row alone.

At 300k the common low-energy edge is epsilon=0.50543711. Beta=1.0
stream-weight ESS is 3.9995 and the maximum stream mass is 25.29%, so
available weight is shared across the four streams. Quadrature ESS is
about 55,780 and is not an independent-sample count.
The missing-target-fraction bound remains uninformative (log bound zero).
Observed depth stability does not prove unbiased constrained sampling or
exclude every possible unseen contribution. Initialization and mixing
validation remain separate requirements.
At beta=0.9, xi_L_squared=10.17 +/- 20.31 is statistically unresolved
despite depth stability; more depth alone does not improve this estimate.

## Matched comparison at beta 1

Use the 300k NS row and MCMC with a 20,000-step cut and blocks of 128
measurements. NS errors are whole-stream bootstrap standard deviations;
MCMC errors are binned jackknife standard errors. The last column uses
the quadrature sum of the two independent errors.

| Observable | NS at 300k | Direct MCMC | Difference / combined SE |
| --- | ---: | ---: | ---: |
| Mean action density | 0.542317 +/- 0.000995 | 0.5419981 +/- 0.0000043 | +0.32 |
| xi_L_squared | 107.288 +/- 19.128 | 98.764 +/- 2.949 | +0.44 |
| Topological susceptibility | 0.00051316 +/- 0.00001812 | 0.00051145 +/- 0.00000140 | +0.09 |
| G0 | 106.926 +/- 4.446 | 105.625 +/- 0.535 | +0.29 |
| Gk | 82.628 +/- 1.631 | 83.123 +/- 0.328 | -0.30 |

All five integrated estimates agree within 0.5 combined SE. First-order
square-root propagation gives NS xi_L=10.358 +/- 0.923 and MCMC
xi_L=9.938 +/- 0.148. This agreement is encouraging, but only four
independent NS streams underlie the bootstrap errors and mixing checks
are still outstanding.
There is no conditional correlator-bin analysis in this L120 output.
Such a check is useful once depth is established, particularly given
the conditional Gk differences seen in the separate L90 campaign.

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

The eight-stream addition and dependent twelve-stream analysis are now
prepared in [ADD_8_STREAMS_300K.md](ADD_8_STREAMS_300K.md). Each fresh
stream runs as two dependent 150k segments, and the current four 300k
streams are reused unchanged.

Retain the four completed 300k streams. The next statistical step is
eight fresh, independently seeded streams at the same depth and settings,
bringing the total to twelve. Reuse MCMC **22780263**. No further depth
extension of the current four streams is indicated by the observed
screens. At the early pilot rate a fresh 300k stream projects to about
14.4 hours, excluding initialization; this is a planning estimate, not
a measured full fresh-run time. More streams do not guarantee a fixed
square-root improvement in errors, as the L90 campaign demonstrated.

Run a conditional correlator-bin comparison at beta=1.0 and 300k using
the raw UBELIX inputs, inspect acceptance/topology near the target band,
and compare longer source initialization/spacing and increased proposals
as separate validation ensembles. A settings change must not be merged
into the existing ensemble. These checks are particularly relevant to
the conditional Gk differences found at L90 despite integrated agreement.

Continuation **22885157** and analysis **22885274** are now represented
by a completed local analysis through 300k. The records are in
[reported_jobs_20261120.tsv](reported_jobs_20261120.tsv). No new simulation
jobs have been submitted by the assistant as part of this review.
