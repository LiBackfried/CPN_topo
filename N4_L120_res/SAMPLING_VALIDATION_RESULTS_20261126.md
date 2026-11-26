# L120 sampling-validation results checked on 2026-11-26

## Source-prior initialization: local analysis complete

Pulled result: `source_init_23502233_analysis_23502234/`, including its
`completed` marker, inputs, provenance, five CSV tables and three figures.
The inputs identify N=4, L=120, beta=0.7, two cold starts and two hot starts,
with seeds 2126073774 through 2126073777. All nine recorded analysis-source
SHA256 hashes match this checkout. Analysis revision:
`357a8123569ee98a6588a30d2634c279eb9d9eef`.

Verified table sizes: 252 cut-summary rows, 2478 binning rows, 20 ACF
summaries, 16020 ACF-curve rows, and 40 live-spacing-window rows. The ACF
uses 8000 measurements per chain after dropping 2000 of the 10000 cycles.
Raw pilot histories and remote scheduler accounting were not available for
independent reanalysis. The copied tables and plots are the evidence here.

### Autocorrelation and spacing

| Observable | tau_int range across four chains (MC cycles) |
| --- | ---: |
| Action density | 1.593–1.778 |
| G0 | 0.484–0.538 |
| Gk | 0.469–0.513 |
| Q | 0.516–0.566 |
| Q² | 0.461–0.514 |

The convention is tau_int = 1/2 + sum rho(t); independent measurements
therefore have tau_int=0.5. All 20 series found the heuristic self-consistent
window and meet the analysis length criterion. Estimated rho(8) ranges
from -0.0090 to 0.0287 for action and has absolute value at most 0.0129
for G0/Gk/Q/Q². These are small residual correlations, with no uncertainty
interval on rho(8) supplied by this analysis.

Dense action measurements are correlated. After cut 2000, pooling the two
cold chains gives action SE 2.790e-5 at block 1 and 4.862e-5 at block 128;
hot chains give 2.819e-5 and 5.139e-5. The increase occurs mainly by blocks
16–32, with no sustained subsequent increase. G0/Gk/charge errors are much
flatter. Thus a claim that *every MC cycle* is already independent would be
incorrect for the action. The existing **eight-cycle live-point spacing is
supported as a practical choice for these source-prior observables**.

### Warmup and hot/cold agreement

The early-history plot shows the large cold-start transient settling near
the beginning of the run; the full plot shows no persistent separation or
obvious long drift. For each of cuts 20/100/500/1000/2000, every hot-versus-cold
pooled comparison is within **1.20 combined SE** over all seven observables.
At cut 2000, using 128-measurement blocks:

| Observable | Cold2 | Hot2 |
| --- | ---: | ---: |
| Action density | 0.8495467 ± 0.0000486 | 0.8494859 ± 0.0000514 |
| G0 | 6.802 ± 0.558 | 6.955 ± 0.538 |
| Gk | 6.897 ± 0.432 | 6.304 ± 0.341 |
| Topological susceptibility | 0.0041010 ± 0.0000469 | 0.0041663 ± 0.0000465 |

Cut dependence is modest relative to the reported errors. Comparisons of
different cuts reuse observations and must not be treated as independent
significance tests. Source xi² is poorly resolved (cold -5.0 ± 37.8, hot
37.7 ± 40.5); its noisy, sometimes negative estimate is not evidence of a
physical negative correlation length or a useful precise warmup criterion.

An early-window caveat remains. The initializer's 50 live slots occur at
cycles 21, 29, ..., 413. For the two hot starts, their pooled action mean is
**0.8503577**, versus **0.8491112** for slots 2001, 2009, ..., 2393. The
difference is **0.0012465**. If these thinned slots are approximated as
independent, the descriptive SE is 0.0004481, or **2.78 SE**. This uses
sqrt(sum(s_chain,window²)/(4*50)) from the two chains and two windows.
Residual correlation and choosing among several observables/windows are
not included; this is not a global test or proof of thermalization bias.
The analogous cold-window difference is only 0.14 SE. Other hot-window
observables differ by at most 1.56 SE under the same approximation.

Consequently, **20-cycle warmup is broadly reassuring but remains
provisional**, especially for the short hot-start live ensemble. Long-run
cut stability alone can dilute an early transient. If that question needs
to be closed, inspect dense early histories and aggregate more independent
hot-start 50-point windows against a stationary reference. Do not alter
the current proposal-control initialization midway through its campaign.

### Scope of the conclusion

There is no clear persistent source-prior thermalization problem in this
pilot, and spacing eight looks reasonable for the monitored observables.
This does not prove independence of all live configurations, exclude
unobserved slow modes, or establish constrained-chain mixing at deeper NS
cutoffs. It also does not by itself explain or remove the existing target
beta=1 conditional G0 discrepancy. The separate proposal-count check below
provides the next piece of evidence.

## Doubled-proposal NS: completed comparison now pulled

The copied campaign `sampling_validation.6xXcOg/jobs.tsv` confirms the
reported submission graph: batch 1 is 23502235 -> 23502236 -> **23502237**;
batch 2 is 23502238 -> 23502239 -> **23502240**. Proposal analysis
**23502241** was queued after those two leaves and compares separate baseline24
(86400 proposals/update) and control8 (172800), each at 300k updates,
reusing MCMC 22780263.

After the source-only review, the user reported completion and pulled
`proposals172800_23502237_analysis_23502241/` on the same date. Its
completion marker, inputs, tables, two comparison figures, joint diagnostics
and provenance are present. All nine recorded analysis-source hashes match
this checkout; analysis revision is
`786cdfb8d21c03f9a8c6bcca8c91d4df20934e8b`.
Verified counts: twelve observable rows, seventy direct-difference rows,
three depth rows, and per cohort 32 bin rows, 64 covariance rows and 64
simultaneous-interval rows. Raw NS histories and remote accounting were not
independently rechecked. Completion here is established from the copied
analysis and the user's report, not a fresh Slurm query.

### Depth

At beta=1 the control8 estimates are unchanged at displayed precision from
**270k to 300k** updates, including the paired bootstrap depth shifts. The
target-weight 99% location is about 237660 points per stream. The last-tenth
target mass falls from 3.66e-4 at 270k to 4.08e-21 at 300k. The 240k
common action cutoff is 0.536675, above the first MC bin edge, and its
last-tenth mass is 0.9995; it is too close to the target region for a depth
claim. At 270k the cutoff is 0.520555 and at 300k it is 0.505637, below
all comparison bins. These are observational depth-stability checks. The
reported log missing-fraction bound remains zero, an uninformative upper
bound of one, so there is no rigorous omitted-tail guarantee.

### Canonical observables at beta=1

NS errors below are whole-stream bootstrap SE, using 200 draws per cohort.
MCMC retains the existing cut 20000 and block 512 measurements; its error
audit was outside this requested study.

| Observable | Baseline24, 86400 proposals | Control8, 172800 proposals | MCMC |
| --- | ---: | ---: | ---: |
| Action density epsilon | 0.5420055 ± 0.0002620 | 0.5426145 ± 0.0003742 | 0.5419982 ± 0.0000044 |
| xi² | 83.22 ± 8.91 | 82.61 ± 8.93 | 98.79 ± 2.96 |
| 10000 chi_t | 5.2004 ± 0.0944 | 5.1550 ± 0.0882 | 5.1145 ± 0.0142 |
| G0 | 102.45 ± 1.70 | 106.41 ± 2.68 | 105.63 ± 0.53 |
| Gk | 83.42 ± 0.80 | 86.76 ± 1.48 | 83.12 ± 0.31 |

Doubling proposals does not recover the MC xi² central value: its direct
cohort shift is only 0.05 independent NS SE. Control G0 moves closer to MC,
but Gk moves upward to 2.40 combined SE above MC. Baseline-minus-control
shifts are -1.33 SE for action, +0.35 for susceptibility, -1.25 for G0 and
-1.98 for Gk. These use NS-only errors because the common MC reference
cancels. They are not independent global tests of all observables.

### Conditional discrepancy remains

Both cohorts use the same 32 fixed MC-derived action bins and a common
NS cutoff, with a joint comparison across all G0/Gk components:

| Cohort | Max absolute z | Simultaneous 95% critical z | Approximate joint p |
| --- | ---: | ---: | ---: |
| Baseline24 | 4.169 | 3.372 | 0.000999 |
| Control8 | 3.695 | 3.252 | 0.017982 |

The baseline p is at the resolution floor of 1000 joint draws. Different
seeds/draws explain modest changes from the earlier stream-count report;
the baseline point estimates are the same. Both rows exceed their joint
95% threshold under the existing bootstrap model. The larger control p
does not demonstrate improved sampling: there are only eight control
streams, with different seeds and generally wider conditional errors.

At the original G0 **bin 9**, epsilon 0.540418465–0.540642218, NS-minus-MC
changes from **-25.445 ± 6.103** to **-12.405 ± 12.174**. The direct
baseline-minus-control shift is **-13.040 ± 12.981**, only **-1.00 SE**.
Thus the weaker local significance does not establish removal of that dip.
Control's largest residual is instead G0 **bin 20**, **+38.790 ± 10.499**
(3.69 SE); G0 bins 8 and 24 are about -3.27 and +3.25 SE.

There is also sensitivity between cohorts in other bins: at G0 bin 24 the
control estimate exceeds baseline by **34.926 ± 8.740** (4.00 marginal SE),
and at bin 20 by **39.738 ± 12.684** (3.13 SE). These are selected local
comparisons among 64 components. A joint baseline-versus-control test was
not computed; the two quoted joint p values each compare a cohort with
MC. Eight independent control streams also limit bootstrap calibration and
the separation of proposal effects from stream-to-stream variation.

### Action-distribution mismatch: clarification after the user's observation

The action distributions must be checked separately from their mean.
Focusing on control8's mean-action difference of 1.65 combined SE understated
its shape mismatch. With the already exported action-bin errors included,
the baseline24 mass residuals have maximum absolute marginal z **1.21**
across 32 bins. In control8, the three lowest-action bins have residuals
**-3.88, -4.74 and -4.99 SE**. Thus the doubled-proposal cohort has a clear
low-action deficit under the current bootstrap error model. These are
correlated marginal comparisons; an action-distribution joint test was not
computed. Small-cohort bootstrap calibration remains a limitation.

The new [action plot with uncertainty bands](../N4_volume_benchmark/action_distribution_review_20261126/L120_action_distributions_with_errors.png)
shows the two cases side by side, with a standardized bin-mass residual
panel. Its source CSV hashes are saved alongside it. The original comparison
plots showed action density without error bands, which made visual deviations
difficult to assess statistically.

For a canonical mean, both factors matter:

`<G0> = integral p(epsilon) <G0 | epsilon> d epsilon`.

At the existing 32-bin resolution, the symmetric decomposition of the G0
NS-minus-MC difference is:

| Contribution | Baseline24 | Control8 |
| --- | ---: | ---: |
| Different action-bin weights | -0.079 ± 0.449 | -0.832 ± 0.559 |
| Different conditional G0 means within bins | -3.189 ± 1.728 | +1.688 ± 2.580 |
| Effect of the omitted comparison tails | +0.086 ± 0.065 | -0.076 ± 0.122 |
| Full G0 difference | -3.182 ± 1.785 | +0.781 ± 2.728 |

The decomposition is an exact algebraic identity for these binned summaries;
the contribution errors are correlated and must not be added in quadrature.
It shows that differences in probabilities assigned to the existing bins
do not account for most of baseline24's G0 offset. Nevertheless, the bins
have finite width: different action distributions *inside* a bin can change
its conditional G0 mean. These panels are not an exact fixed-action test.
Finer binning or explicit matching of within-bin action distributions would
be needed to separate that effect cleanly. The present data do not isolate
a purely correlator- or topology-specific mixing failure.

### Interpretation and next step

**The tested doubling is not a demonstrated resolution of the conditional
disagreement.** Target-depth stability is reassuring, but the conditional
pattern changes, the new cohort still exceeds its joint threshold, and
its action-distribution shape also differs from MC.
Neither a monotonic approach to the MC answer nor convergence with proposal
count is established. Keep baseline24 and control8 separate.

The next informative experiment is a stationary constrained-chain mixing
check at fixed representative action cutoffs spanning the affected bins,
with independent starts and measured autocorrelation/relaxation of action,
G0, Gk and charge. It would help distinguish insufficient constrained-chain
mixing from the variation between small independent stream cohorts. Source
initialization should remain explicitly controlled; its 20-cycle warmup
caveat above is still open. This is a proposed follow-up, not a prepared or
submitted campaign.
