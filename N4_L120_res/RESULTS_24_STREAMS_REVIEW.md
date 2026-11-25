# L120: 24 streams through 300k updates, reviewed 2026-11-25

The completed [stream-count follow-up](STREAM_COUNT_RESULTS.md) now supplies
the joint diagnostic absent from this production output. It confirms the
precision scaling and reproduces the conditional G0 offset in both disjoint
twelve-stream cohorts; pooled full24 joint p is approximately 0.002. The
production numbers and limitations below are retained as the earlier baseline.

The copied analysis **23350708** is complete in
`combined24x300_analysis_23350708/`. It combines **24 independently seeded
NS streams**, each at **300,000 cumulative updates**, and reuses direct
beta=1.0 MCMC **22780263**. NS source beta remains 0.7, with 50 live points
per stream, 86,400 proposals/update and a combined live count of 1,200.

The depth checks still pass through beta=1.0 and the integrated observables
remain within 1.8 combined SE of MCMC. More streams reduce the statistical
errors but leave the highlighted conditional G0 residual approximately
unchanged in magnitude. Its marginal standardized discrepancy is now 4.42;
this output does not supply a 24-stream joint p-value.

## Completion and provenance

The user reported all L120 runs completed and pulled on 2026-11-25. The
local analysis has a `completed` marker, all expected depth/MCMC/bin outputs,
six NS leaf roots plus one MCMC root in `inputs.tsv`, and matching hashes
for all seven recorded analysis source files. The depth table has exactly
15 rows, covering five prefixes and three target betas, all marked L120
and 24 streams. The copied seed plan contains 24 distinct positive seeds.
Raw simulation histories and current remote Slurm state were not inspected
independently; the checked launcher/scanner validate those inputs on UBELIX.

The six NS leaves are **22885157, 22904262, 22904264, 23350703, 23350705,
23350707**. New starts **23350702/23350704/23350706** supply the preceding
150k segments of the last three leaves. Their repeated checkpoint rows are
removed by the scanner, so segment pairs count as four streams, not eight.
The copied campaign directory is `add12_to24_300k.5QBVa7/`; its manifest and
retry command agree with the analysis inputs and reported job IDs.

Both full-history and 20,000-step-cut MCMC `binning.csv` files are byte-
identical to the earlier twelve-stream analysis's MCMC copies. Changes in
NS results therefore do not come from a changed MCMC reference. The main
comparison below uses blocks of 512 measurements (5,120 MC cycles).

## Depth and coverage

| Target beta | q99 points/stream at 300k | Final-tenth mass at 300k | First tested prefix passing observed edge/stability screens |
| --- | ---: | ---: | --- |
| 0.90 | 130,352.21 | 3.15e-308 | 180k |
| 0.95 | 183,663.83 | 6.69e-118 | 210k |
| 1.00 | 239,321.33 | 3.68e-21 | 270k |

At all three targets, **270k and 300k means and paired 95th-percentile shift
bounds agree to saved numerical precision** for every reported statistic.
At beta=1.0, final-tenth mass falls from 99.9931% at 240k to **0.1548% at
270k**, then 3.68e-21 at 300k. At 240k the paired action shift bound is
0.00011212, about 40.7% of the final NS action SE, exceeding the working
10%-of-statistical-error truncation budget. The 270k prefix has a distinct,
deeper 300k reference and passes both observed screens.

At beta=1.0, stream-weight ESS is **23.9989**, the largest stream mass is
**4.23%**, and quadrature ESS is **338,105**. These measure weight
concentration, not independent configuration counts. The missing-target
fraction bound remains uninformative (log bound zero). Depth stability
does not establish unbiased initialization or constrained sampling. These
results give no reason for another production depth extension.

Source: [depth.csv](combined24x300_analysis_23350708/depth.csv).

## Integrated beta=1.0 comparison

Use the 300k NS row and pooled MCMC after the 20,000-MC-step cut, with
512-measurement blocks. Errors are whole-stream bootstrap SEs for NS and
delete-block jackknife SEs for MCMC. Differences combine independent NS
and MCMC errors in quadrature.

| Observable | NS, 24 streams | Direct MCMC | NS-MCMC / combined SE |
| --- | --- | --- | ---: |
| Action density | 0.54200555 +/- 0.00027564 | 0.54199822 +/- 0.00000440 | +0.03 |
| xi_L_squared | 83.2195 +/- 8.9315 | 98.7902 +/- 2.9600 | -1.65 |
| Topological susceptibility | 0.000520045 +/- 0.000009678 | 0.000511451 +/- 0.000001419 | +0.88 |
| G0 | 102.4463 +/- 1.7065 | 105.6281 +/- 0.5288 | -1.78 |
| Gk | 83.4186 +/- 0.8309 | 83.1208 +/- 0.3072 | +0.34 |

NS xi_L is **9.122 +/- 0.490**, using first-order error propagation from
xi_L_squared. The integrated results remain compatible at the two-combined-
SE level, but G0 and xi_L_squared move below MCMC as precision increases.
This does not establish equivalence or absence of bias.

Sources: [depth.csv](combined24x300_analysis_23350708/depth.csv),
[MCMC binning](combined24x300_analysis_23350708/mcmc_burn20000/binning.csv),
and [correlator summary](combined24x300_analysis_23350708/action_bins32_beta1p0_block512/summary.csv).

## Precision relative to the earlier twelve-stream production analysis

| Observable | Twelve-stream SE | Twenty-four-stream SE | SE ratio (24/12) |
| --- | ---: | ---: | ---: |
| Action density | 0.00046957 | 0.00027564 | 0.587 |
| xi_L_squared | 12.0102 | 8.9315 | 0.744 |
| Susceptibility | 0.000013729 | 0.000009678 | 0.705 |
| G0 | 2.4306 | 1.7065 | 0.702 |
| Gk | 1.1019 | 0.8309 | 0.754 |

Most errors decrease by about 25-30%, near the ideal independent-stream
factor 1/sqrt(2); action improves by about 41%. These are descriptive ratios
from 200-replicate bootstrap runs with different seeds. The old twelve
streams are a subset of the new 24: their central-value shifts must not
be assigned a significance by treating the two estimates as independent.
Twelve-stream source: `combined300_ns22885157_analysis_22904265/depth.csv`.

## Conditional correlators

The 32-bin beta=1.0 comparison uses blocks of 512 measurements. Its largest
G0 residual, bin9 at epsilon **0.5404184648-0.5406422176**, is
**NS-MCMC = -25.4450 +/- 5.7633**, or **-4.415 marginal SE**. The corresponding
range in the earlier twelve-stream robustness result gave -24.6816 +/-
8.1018 (-3.046 SE). Edges differ very slightly because the new comparison
sets its quantiles using the 512-block support, whereas the earlier
robustness grid froze edges from the 128-block support.

The absolute offset therefore persists while its error shrinks. Four of
32 G0 bins exceed two marginal SE; one exceeds three. The maximum Gk
residual is 2.030 SE, with one of 32 bins exceeding two and none exceeding
three. Do not treat these marginal maxima as calibrated global significance.
The 24-stream output has no covariance/joint-bootstrap files or bin/block
grid; the earlier twelve-stream joint p about 0.085 cannot be transferred
to this enlarged ensemble.

Sources: [bins.csv](combined24x300_analysis_23350708/action_bins32_beta1p0_block512/bins.csv)
and [comparison plot](combined24x300_analysis_23350708/action_bins32_beta1p0_block512/comparison.png).

## Next priorities

Use these 24 streams as the current L120 production estimate, retaining
the twelve-stream analyses as historical baselines. Additional production
depth is not indicated. Repeat joint bin/block diagnostics on all 24 streams
and compare the old and newly added twelve-stream ensembles as disjoint
groups. Keep source-beta thermalization/live-point-spacing and constrained-
mixing validation separate from increasing statistics. The smaller errors
make the persistent conditional G0 offset more important to investigate;
they do not identify which sampler or error-model assumption causes it.
