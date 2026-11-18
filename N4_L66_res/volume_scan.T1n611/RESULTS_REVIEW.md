# Seven-beta volume scan: results review

Reviewed the copied outputs of analysis jobs **22622025** (L22), **22622026** (L38), **22622027** (L66), and comparison job **22622028**. All four copied logs end with their expected output messages and contain no traceback or fatal error. Remote Slurm state was not queried.

All 21 requested NS beta/volume combinations and three direct MCMC reference points are present. Checked stream counts, proposal counts, 200 bootstrap replicates per volume, comparison-table dimensions, and single-stream weight normalization.

## Ensembles

| L | Independent NS streams | NS updates each | Proposals per update | Direct MCMC reference |
|---|---:|---:|---:|---|
| 22 | 100 reproducibly selected from 800 | 50,000 | 1,500 | beta=0.7, job 21347214 |
| 38 | 24 | 35,000 | 8,664 | beta=1.0, job 22121710 |
| 66 | 12 | 110,000 | 26,136 | beta=0.9, job 22587511 |

Every NS stream has 50 live points and source beta=0.7, theta=0. MCMC errors use a 20,000-MC-step burn-in cut and blocks of 128 measurements. NS errors resample whole independently seeded streams.

## Matched NS/MCMC checks

The table gives (NS - MCMC) divided by the quadrature sum of their independent statistical standard errors. These are single comparisons, not an omnibus goodness-of-fit test.

| L | beta | Action density shift / SE | xi^2 shift / SE | chi_top shift / SE | G0 shift / SE | Gk shift / SE |
|---|---:|---:|---:|---:|---:|---:|
| 22 | 0.70 | +0.08 | -1.58 | +0.13 | -1.59 | +0.24 |
| 38 | 1.00 | -0.20 | -0.62 | +0.55 | -0.72 | +0.18 |
| 66 | 0.90 | +0.27 | +0.32 | +0.32 | +1.46 | +1.50 |

All matched action, xi-squared, susceptibility and correlator estimates are within 1.6 combined SE. The largest offset among all saved matched observables is the L22 mean cooled charge: NS 0.03544 +/- 0.01268 versus MCMC 0.00115 +/- 0.00081 (2.70 combined SE). This warrants monitoring with more independent NS seeds; one offset across multiple correlated observables is not proof of bias.

MCMC error estimates are broadly stable across block sizes 64 through 1024 for action, xi-squared and susceptibility in all three volumes. Binning agreement supports the selected errors but does not prove equilibration of every slow mode.

## Reweighted observables

Errors below are standard deviations across 200 whole-stream bootstrap replicates. Signed xi-squared estimates are retained even when their square roots are undefined.

| L | beta | Mean action density | xi^2 | chi_top |
|---|---:|---:|---:|---:|
| 22 | 0.70 | 0.849501 +/- 0.000245 | 2.697 +/- 0.302 | 0.0040339 +/- 0.0000582 |
| 22 | 0.75 | 0.780550 +/- 0.000274 | 5.138 +/- 0.202 | 0.0033454 +/- 0.0000258 |
| 22 | 0.80 | 0.718456 +/- 0.000415 | 9.224 +/- 0.198 | 0.0026224 +/- 0.0000191 |
| 22 | 0.85 | 0.663752 +/- 0.000415 | 16.674 +/- 0.246 | 0.0017296 +/- 0.0000150 |
| 22 | 0.90 | 0.614524 +/- 0.000387 | 31.909 +/- 0.395 | 0.0008618 +/- 0.0000145 |
| 22 | 0.95 | 0.573626 +/- 0.000366 | 51.818 +/- 0.475 | 0.0003269 +/- 0.0000103 |
| 22 | 1.00 | 0.538234 +/- 0.000410 | 70.997 +/- 0.472 | 0.0000988 +/- 0.0000051 |
| 38 | 0.70 | 0.849079 +/- 0.000378 | -0.652 +/- 1.873 | 0.0041207 +/- 0.0001022 |
| 38 | 0.75 | 0.780294 +/- 0.000427 | 4.803 +/- 1.074 | 0.0034902 +/- 0.0000343 |
| 38 | 0.80 | 0.718910 +/- 0.000386 | 8.848 +/- 0.693 | 0.0027426 +/- 0.0000251 |
| 38 | 0.85 | 0.663486 +/- 0.000697 | 16.680 +/- 0.861 | 0.0019900 +/- 0.0000217 |
| 38 | 0.90 | 0.617004 +/- 0.000725 | 30.028 +/- 1.067 | 0.0013485 +/- 0.0000184 |
| 38 | 0.95 | 0.577178 +/- 0.000476 | 54.438 +/- 1.612 | 0.0008179 +/- 0.0000199 |
| 38 | 1.00 | 0.540828 +/- 0.000765 | 105.555 +/- 3.033 | 0.0003689 +/- 0.0000143 |
| 66 | 0.70 | 0.849338 +/- 0.000268 | -9.156 +/- 23.765 | 0.0039395 +/- 0.0001462 |
| 66 | 0.75 | 0.780312 +/- 0.000415 | -5.559 +/- 7.882 | 0.0035087 +/- 0.0000388 |
| 66 | 0.80 | 0.719467 +/- 0.000603 | 12.857 +/- 3.051 | 0.0027710 +/- 0.0000338 |
| 66 | 0.85 | 0.664594 +/- 0.000442 | 21.398 +/- 2.201 | 0.0019936 +/- 0.0000137 |
| 66 | 0.90 | 0.617279 +/- 0.000586 | 30.771 +/- 2.748 | 0.0013602 +/- 0.0000179 |
| 66 | 0.95 | 0.577418 +/- 0.000624 | 53.195 +/- 3.446 | 0.0008392 +/- 0.0000154 |
| 66 | 1.00 | 0.541976 +/- 0.000933 | 106.282 +/- 6.814 | 0.0005107 +/- 0.0000120 |

## Observed volume dependence

At beta=1.0 the susceptibility is:

| L | chi_top | xi | L/xi |
|---|---:|---:|---:|
| 22 | 0.0000988 +/- 0.0000051 | 8.426 +/- 0.028 | 2.61 |
| 38 | 0.0003689 +/- 0.0000143 | 10.274 +/- 0.148 | 3.70 |
| 66 | 0.0005107 +/- 0.0000120 | 10.309 +/- 0.329 | 6.40 |

L22 separates strongly from the larger volumes in susceptibility from about beta=0.85 onward. At beta=1.0, L66 minus L38 susceptibility is 0.00014178 +/- 0.00001861, or 7.62 combined statistical SE. In contrast, L38/L66 xi-squared values agree within 0.10 combined SE there. Their xi/L values differ because L differs; that ratio alone does not establish a shift in the absolute correlation length.

These are measured differences between the chosen setups. Their interpretation as purely physical volume effects also depends on constrained-chain mixing and initialization checks: the volumes use different stochastic proposal counts. The direct MCMC checks support three individual beta/volume points, not every grid point.

## Unresolved low-beta correlation lengths

| L | beta | xi^2 +/- SE | Fraction of bootstrap replicates with finite xi |
|---|---:|---:|---:|
| 38 | 0.70 | -0.652 +/- 1.873 | 0.360 |
| 66 | 0.70 | -9.156 +/- 23.765 | 0.270 |
| 66 | 0.75 | -5.559 +/- 7.882 | 0.275 |

At these points mean G0/Gk is too noisy to establish a positive central xi-squared. NaN xi and xi/L entries are intentional. Finite replicates must not be selected and treated as an unbiased xi bootstrap. More NS depth does not improve source-beta statistics: 99% of source weight lies in approximately the first 230 ranked points per stream. Additional independent streams or direct low-beta MCMC measurements address the statistical limitation more directly.

## Reweighting support and weights

| L | beta=1 q99 points per stream | Available NS updates | Last-tenth target mass at beta=1 | Stream-weight ESS at beta=1 |
|---|---:|---:|---:|---:|
| 22 | 9888.3 | 50,000 | 8.12e-177 | 99.960 / 100 |
| 38 | 26574.5 | 35,000 | 3.39e-08 | 23.993 / 24 |
| 66 | 75213.5 | 110,000 | 8.87e-31 | 11.997 / 12 |

No observed low-energy-edge pileup is visible at the tested depths. Stream-weight ESS stays close to the number of included streams at every beta, so no observed single-stream domination is present. Quadrature ESS is not an independent Markov-chain sample count. The conservative missing-target-fraction bound is uninformative (log bound 0) for L38/L66 at beta >=0.8. Small edge mass and balanced stream weights do not exclude unseen target mass or constrained-sampling bias.

Every stored single-stream curve sums to one within 1e-12. All logarithmic weights are finite, including tails that underflow when exponentiated. Peak ranks of the selected single streams are listed below; these are illustrative individual-stream diagnostics rather than ensemble support estimates.

| L | Maximum absolute normalization error | Peak ranks for beta=0.70,0.75,...,1.00 |
|---|---:|---|
| 22 | 3.16e-14 | 0, 401, 1423, 2545, 4235, 6429, 7284 |
| 38 | 2e-13 | 0, 1086, 3629, 7658, 11782, 16742, 23252 |
| 66 | 3.28e-13 | 0, 2898, 10891, 22462, 36333, 50400, 69672 |

## Next useful checks

1. Keep the current NS depth for now; the saved edge and prior prefix-stability screens provide no reason for a depth extension solely to repeat this grid.
2. A direct L66 MCMC measurement at beta=1.0 would test the largest remaining L38/L66 topology difference at matched beta. The existing L38 beta=1.0 MCMC reference is already available.
3. For low-beta correlation lengths at large volume, prioritize independent source statistics and initialization/mixing checks. Keep those checks separate from the depth question.

## Files

- [Volume comparison plot](volume_dependence.png) and [PDF](volume_dependence.pdf).
- [All values and errors](volume_comparison.csv).
- [NS/MCMC differences](ns_mcmc_comparison.csv).
- [Volume differences](volume_shifts.csv).
- [Coverage diagnostics](coverage_diagnostics.png).
- Per-volume `L22/`, `L38/`, `L66/`: beta tables, selected inputs, and normalized-weight overlays.
