# L66 results review

Reviewed the copied analysis outputs from NS jobs 22587433–22587435
(12 independently seeded streams, 110,000 updates each) and direct MCMC
job 22587511 (three chains, beta=0.9). Both `campaign.HP4pX0/` and
`comparison_22587511/` contain a `completed` marker. Their `depth.csv`
files are byte-identical. This review uses the saved summaries and plots;
raw simulation/checkpoint files and remote Slurm state were not inspected,
and no bootstrap was rerun locally.

## Matched comparison at beta=0.9

Use the 110,000-update NS row and the pooled MCMC row with a 20,000-step
burn-in cut and blocks of 128 measurements (1,280 MC steps). Each MCMC
chain retains 98,000 measurements before dropping incomplete blocks;
the block analysis uses 97,920 per chain, 293,760 total. NS errors are
whole-stream bootstrap standard deviations; MCMC errors are binned
jackknife errors. Differences below divide by the quadrature sum of the
two independent errors.

| Observable | Reweighted NS | Direct MCMC | NS minus MCMC / combined SE |
| --- | ---: | ---: | ---: |
| Mean action density | 0.617279 ± 0.000601 | 0.6171198 ± 0.0000093 | +0.265 |
| xi_L_squared | 30.771 ± 2.739 | 29.865 ± 0.791 | +0.318 |
| Topological susceptibility | 0.00136015 ± 0.00001860 | 0.00135434 ± 0.00000353 | +0.307 |

All three agree within about 0.3 combined standard errors. Propagating the
xi_L_squared errors through the square root gives:

- NS: xi_L = 5.547 ± 0.247.
- MCMC: xi_L = 5.465 ± 0.072.
- User's matching L66, beta=0.9 table: xi_L = 5.398 ± 0.022.

The NS/table and MCMC/table differences are respectively about 0.60 and
0.88 combined SE. These are first-order error estimates for the square
root, not a new bootstrap of xi_L.

MCMC bin errors are broadly stable over 64–1024 measurements: for
xi_L_squared the pooled error varies from 0.789 to 0.816, and for topology
from about 3.50e-6 to 3.60e-6. The separate chain xi_L_squared values at
block size 128 are 29.14 ± 1.34, 29.97 ± 1.43 and 30.49 ± 1.34.
Histories show frequent cooled-Q sector transitions (86,563, 86,461 and
86,597 after the cut) and no obvious persistent action drift. These are
reassuring diagnostics, not a proof that every slow mode is equilibrated.

## Depth through beta=1.0

At beta=0.9, 40k updates remain truncated: the last tenth of merged ranks
carries about 77.7% of target weight. By 60k this drops to 1.18e-17 and
the reported observables and paired-bootstrap shifts agree with 110k to
the saved numerical precision. The final q99 is about 41,594 points per
stream, consistent with needing more than a 40k prefix.

At beta=1.0, 60k is inadequate. At 80k the last-tenth weight is still
22.2%, although the observables are already close to their final values.
At 100k it is 6.59e-16, and all reported observables match 110k to the
saved precision. At 110k it is 8.87e-31. Thus **110k is sufficient for
the observed prefix-stability and edge-mass screens through beta=1.0**;
the scan provides no reason to extend these streams just for that screen.

The beta=1.0 result is xi_L_squared = 106.28 ± 6.52 (xi_L approximately
10.309 ± 0.316). The table's beta=1.0 point is at L120, so it is not a
matched-volume reference. There is no direct beta=1.0 L66 MCMC comparison
in these outputs.

The missing-target-fraction bound remains
uninformative: `log_missing_target_fraction_bound` is 0 at beta=0.9 and
1.0. Small observed edge weights and prefix agreement do not exclude an
unseen contribution or constrained-sampling bias. Stream-weight ESS is
about 12 at both targets, so observed weights are spread across the twelve
streams. Quadrature ESS (about 79k at beta=0.9 and 94k at beta=1.0) is
not a number of independent Markov-chain samples. NS acceptance histories
and initialization/proposal-count comparisons are not included here.

## Correlator-bin check

`comparison_22587511/action_bins32_beta0p9/summary.csv` reports:

| Observable | NS | MCMC | Difference / combined SE |
| --- | ---: | ---: | ---: |
| G0 | 39.999 ± 0.760 | 38.896 ± 0.175 | +1.41 |
| Gk | 31.282 ± 0.428 | 30.616 ± 0.107 | +1.51 |

About 98.88% of NS mass and 99.00% of MCMC mass fall in the shared range.
The integrated correlator offsets come mainly from within-bin differences:
G0 contributes 1.215 ± 0.646 and Gk 0.744 ± 0.368; bin-mass differences
are small relative to their errors. The per-bin errors are correlated,
so individual deviations across 32 bins should not be counted as
independent evidence. These residuals merit monitoring with more NS seeds,
but the integrated offsets are only about 1.4–1.5 SE and the matched
correlation-length result agrees well.

## Limitation at low target beta

The beta=0.7 and 0.75 NS xi_L_squared estimates are respectively
**-9.16 ± 21.78** and **-5.56 ± 7.72**. Their saved mean G0 is below mean
Gk; the estimates are unresolved and do not define a real central xi_L.
The physically positive xi_L_squared is not established by these noisy
estimates. On this large volume the small-momentum correlator ratio is
close to one for a short correlation length, making this difference
sensitive to noise. These results cannot be used as successful low-beta
correlation-length validation. More depth does not improve them: the
source-weighted results already stop changing at early prefixes. More
independent source statistics, plus source-initialization/mixing checks,
are needed for a reliable low-beta determination.

The current evidence supports the matched beta=0.9 comparison and the
depth screen through beta=1.0. If the next objective is smaller statistical
errors at beta=0.9, prioritize additional independent NS streams and
mixing checks over extending these already deep streams.

## Files

- `comparison_22587511/depth.csv`: depth and whole-stream bootstrap results.
- `comparison_22587511/mcmc_burn20000/binning.csv`: MCMC estimates/errors.
- `comparison_22587511/mcmc_burn20000/histories.png` and `binning.png`:
  equilibration and bin-size diagnostics.
- `comparison_22587511/action_bins32_beta0p9/comparison.png` and
  `summary.csv`: common-bin correlator comparison.
