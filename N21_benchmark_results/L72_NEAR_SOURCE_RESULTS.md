# N=21 L=72 near-source results

Reviewed on 25 November 2026 from the [pulled analysis](near_source_23365849).
The copy contains the completion marker and all six CSVs. The three recorded
analysis source hashes match the local checkout. The two new jobs are 23365847
and 23365848, with ten independently seeded streams per proposal count. The
original ten streams per proposal count were pooled with the new streams at
a common 5,000-update depth. This review uses the aggregate outputs.

## Depth

For these L=72 runs, **500 NS updates per stream cover β=0.60** at the current
precision. **2,000 updates cover β=0.61** in the tested prefixes. The 5,000-step
prefix provides extra margin and agrees with 20,000 steps to the numerical
precision of the recorded physics estimates.

| Target β | Prefix updates/stream | Last tenth of retained ranks, 15,500 proposals | Last tenth, 31,000 proposals |
| ---: | ---: | ---: | ---: |
| 0.60 | 500 | 0.0157% | 0.0120% |
| 0.61 | 500 | 43.0% | 44.9% |
| 0.61 | 1,000 | 26.6% | 25.5% |
| 0.61 | 2,000 | 0.617% | 0.467% |
| 0.61 | 5,000 | 3.20e-12% | 4.43e-12% |

At β=0.61, the 99% weight rank at full depth is about 1,719 and 1,695 retained
points per stream for the two arms, equivalent to expected `−log X` of 34.38
and 33.89 with 50 live points per stream. At β=0.60 it is about 230 points
per stream, or `−log X = 4.61`. The largest 95th percentile of the absolute
paired shift among the reported physics observables at 2,000 versus 20,000
updates at β=0.61 is 0.144 times the corresponding full-depth bootstrap
standard error. This checks stability along the sampled histories. At β=0.61
the largest stream shares about 10.6% of the observed target weight in each
ten-stream ensemble.

## Pooled observables and the proposal-count comparison

Each NS column uses 20 streams at 5,000 updates per stream with whole-stream
bootstrap errors. Topology uses 25 cooling sweeps. The susceptibility is
centered, so `Vχ = 5184 × chi_topological`. The thesis reference ξ² and its error
are derived by squaring ξ and using first-order error propagation.
The exact cooling count for the thesis table remains undetermined.
[Bonanno, Table 4.2](LITERATURE_COMPARISON.md)

| β | Observable | 15,500 proposals | 31,000 proposals | Thesis simulated tempering |
| ---: | --- | ---: | ---: | ---: |
| 0.60 | E/(NV) | 1.716625 ± 0.000109 | 1.716776 ± 0.000130 | 1.716722 ± 0.000002 |
| 0.60 | ξ² | 14.07 ± 3.32 | 5.53 ± 3.52 | 8.381 ± 0.041 |
| 0.60 | Mean cooled Q | 0.844 ± 0.303 | 0.059 ± 0.391 | 0.002 ± 0.003 |
| 0.60 | Vχ | 3.761 ± 0.628 | 4.641 ± 0.808 | 4.943 ± 0.008 |
| 0.61 | E/(NV) | 1.687715 ± 0.000226 | 1.687820 ± 0.000196 | 1.687663 ± 0.000002 |
| 0.61 | ξ² | 10.40 ± 1.37 | 8.93 ± 1.37 | 9.066 ± 0.048 |
| 0.61 | Mean cooled Q | 0.819 ± 0.328 | −0.063 ± 0.457 | 0.002 ± 0.002 |
| 0.61 | Vχ | 3.055 ± 0.539 | 4.960 ± 0.795 | 4.327 ± 0.006 |

Pooling reduced the standard errors for E/(NV), ξ² and χ relative to the
respective original 10-stream estimates, with gains that vary by observable
and proposal count. At β=0.61 both arms agree with the reference energy
within 0.81 combined standard errors and with ξ² within 0.98.

Topology is the main remaining question. At β=0.61 the 15,500-proposal arm
has mean charge 2.50 standard errors above zero and Vχ 2.36 combined standard
errors below the simulated-tempering reference. Its Vχ is also 2.21 combined
standard errors below the thesis local reference. The 31,000-proposal arm
has a mean charge close to zero and Vχ within 0.80 combined standard errors
of simulated tempering. Vχ is higher with 31,000 proposals in both seed batches
at β=0.61, by 1.71 and 1.77 combined standard errors separately and 1.98 when
pooled. The 15,500 arm also has positive mean Q at β=0.60, 2.78 standard
errors from zero. The two β estimates reuse the same streams. These marginal
comparisons motivate checking constrained mixing and initialization, but the
aggregate results do not identify which mechanism explains the differences.

## N=4 depth comparison

Ran the same depth scanner locally on CP³, L=22, using streams 750–759 from
the copied β=0.70 dataset, with 50 live points, 1,500 proposals and 25 cooling
sweeps. The scan compared β=0.70 and reweighted β=0.71 through 50,000 updates
without a new bootstrap. [Aggregate scan CSV](n4_l22_near_source_depth.csv)

| Comparison | Full-depth 99% rank per stream | Expected −log X at that rank | First tested prefix with less than 1% weight in the last tenth |
| --- | ---: | ---: | ---: |
| N=4, L=22, β=0.70 → 0.71 | 340 | 6.79 | 500 |
| N=21, L=72, β=0.60 → 0.61, 15,500 proposals | 1,719 | 34.38 | 2,000 |
| N=21, L=72, β=0.60 → 0.61, 31,000 proposals | 1,695 | 33.89 | 2,000 |

The nearby shift uses about five times as much expected depth in the N=21
benchmark as in this N=4 comparison. That ratio includes the changes in
lattice size, source coupling and overlap. It cannot be attributed to N
alone. The depth scanner also does not measure autocorrelation at a fixed
cutoff, so this does not yet quantify an N=21 versus N=4 proposal requirement.

Prioritize a same-volume topology check at β=0.60 and 0.61. For fixed-cutoff
pilots, the saved 99% ranks give action-density anchors around 0.8523–0.8524
and 0.8379–0.8381, respectively. Sample cutoffs across the weight-bearing
range to measure charge-sector decorrelation under the two proposal counts.
