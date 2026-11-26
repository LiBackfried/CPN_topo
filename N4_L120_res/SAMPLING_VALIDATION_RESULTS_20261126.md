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
beta=1 conditional G0 discrepancy. The separate proposal-count check is
still needed.

## Doubled-proposal NS: no pulled comparison found

The copied campaign `sampling_validation.6xXcOg/jobs.tsv` confirms the
reported submission graph: batch 1 is 23502235 -> 23502236 -> **23502237**;
batch 2 is 23502238 -> 23502239 -> **23502240**. Proposal analysis
**23502241** waits for those two leaves and compares separate baseline24
(86400 proposals/update) and control8 (172800), each at 300k updates,
reusing MCMC 22780263.

The expected directory
`proposals172800_23502237_analysis_23502241/` is absent locally. No related
raw job directories were found under the available L120 and sibling data
roots. Submission records do not establish current execution or completion
status; this review makes no remote-status claim. No conclusion about the
effect of doubling proposals can yet be drawn from the pulled files.

Once that output is pulled, check its completion marker and settings,
control8 depth convergence, integrated observables, and the conditional
G0/Gk shifts and joint diagnostics against baseline24. Preserve the two
proposal settings as separate ensembles.
