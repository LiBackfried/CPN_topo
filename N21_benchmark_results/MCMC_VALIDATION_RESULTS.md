# N=21 MCMC results and next runs

Reviewed on 26 November 2026. All three pulled analyses have a `completed`
marker. The simulations use four differently seeded hot chains at θ=0.
This review uses worktree aggregates. The raw trajectories and Slurm
accounting were not inspected.

| Campaign | Simulation / analysis | Cycles per chain | Measurement stride | Median wall s/cycle |
| --- | --- | ---: | ---: | ---: |
| [L=72, β=0.61 direct reference](mcmc_L72-b061_23502101/) | 23502100 / 23502101 | 200,000 | 10 | 0.03220 |
| [L=72, β=0.60 prior check](mcmc_L72-b060_23502108/) | 23502107 / 23502108 | 20,000 | 1 | 0.12257 |
| [L=150, β=0.60 timing](mcmc_L150-timing_23502111/) | 23502110 / 23502111 | 2,000 | 1 | 0.60208 |

## L=72 direct MCMC comparison

The NS numbers use the first 5,000 updates of each of the 20 streams per
arm in the [near-source analysis](near_source_23365849/). MCMC errors use
complete blocks after cuts of 5,000 cycles at β=0.60 and 20,000 at β=0.61.
The selected block sizes are 512 and 10,240 cycles, respectively, the
largest exported at those cuts. At β=0.60 the topology errors are still
growing with block size. NS errors use the whole-stream bootstrap. Both
analyses use geometric charge at 25 cooling sweeps. The signed residual
is (NS − MCMC) divided by the quadrature sum of their standard errors.
These are individual comparisons between correlated observables.

| β | Observable | Direct MCMC | NS, 15,500 proposals | Residual | NS, 31,000 proposals | Residual |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 0.60 | ⟨E⟩/(NV) | 1.716665(55) | 1.716625(109) | −0.33 | 1.716776(130) | +0.79 |
| 0.60 | ξ² | 7.95(66) | 14.07(3.32) | +1.81 | 5.53(3.52) | −0.68 |
| 0.60 | ⟨Q_U⟩ | 0.355(169) | 0.844(303) | +1.41 | 0.059(391) | −0.69 |
| 0.60 | Vχ_t | 5.368(402) | 3.761(628) | −2.15 | 4.641(808) | −0.81 |
| 0.61 | ⟨E⟩/(NV) | 1.687628(24) | 1.687715(226) | +0.38 | 1.687820(196) | +0.97 |
| 0.61 | ξ² | 9.77(65) | 10.40(1.37) | +0.42 | 8.93(1.37) | −0.55 |
| 0.61 | ⟨Q_U⟩ | −0.102(69) | 0.819(328) | +2.75 | −0.063(457) | +0.08 |
| 0.61 | Vχ_t | 4.476(199) | 3.055(539) | −2.47 | 4.960(795) | +0.59 |

At β=0.61, after the 20,000-cycle cut, the four direct chains show
2,744–2,786 charge-sector transitions between stored measurements each.
Integrated autocorrelation times range from 300 to 714 cycles for Q_U
and from 201 to 374 cycles for Q_U². The pooled Q_U error at block sizes
2,560, 5,120 and 10,240 cycles is 0.072, 0.073 and 0.069. The susceptibility
error at those blocks is 0.179, 0.183 and 0.199. The direct MCMC values
are also within 1.6 combined SE of the corresponding simulated-tempering
values in the [Bonanno thesis comparison](LITERATURE_COMPARISON.md), using
ξ² with propagated error. The thesis cooling count is unconfirmed.

Use 31,000 proposals as the working setting for the next controlled L=72
test. All four reweighted values agree with direct MCMC within one
combined SE, while the 15,500-proposal arm has larger charge and
susceptibility differences. The existing depth scan supports keeping
5,000 NS updates for that test. Both arms used the same short warmup and
live-point spacing, so the data cannot isolate the contribution of
constrained updates from prior initialization.

## L=72 live-point warmup and spacing

The current initializer uses a single hot chain per stream, discards
20 cycles, then saves 50 configurations at cycles 21, 29, …, 413.
Regular MCMC uses the same update sequence of four microcanonical sweeps
and one overheatbath sweep. It also explicitly normalizes the fields
every cycle.

After discarding 5,000 cycles of the direct β=0.60 runs, the observed
lag-eight correlations across the four chains are 0.053–0.078 for the
action density, −0.014–0.005 across G₀ and Gₖ, 0.964–0.981 for Q_U and
0.898–0.959 for Q_U². At lag 512, Q_U autocorrelations still range from
0.067 to 0.303. Three of the four Q_U autocorrelation windows are
unresolved. The fourth gives τ_int ≈ 119 cycles and is flagged as having
limited history. Q_U² gives τ_int ≈ 74–123 cycles in the three chains
with finite estimates, two flagged for limited history. The convention
is τ_int = ½ + Σρ, in MC cycles.

The first 50-point windows give mean Q_U² of 0.50, 1.84, 1.82 and 7.80
across chains. The corresponding windows after 5,000 cycles give 1.52,
3.12, 8.76 and 3.64. The later windows keep the same eight-cycle spacing,
so this comparison cannot isolate warmup bias. At the 5,000-cycle cut,
the pooled Q_U error grows from 0.101 at block length 128 to 0.169 at
512. Each chain visits 12–17 sectors after this cut, but the sustained
ACF and growing block errors show why transition counts alone are
insufficient.

Eight cycles are much too short to treat the initial live points as
independent in topology. The pilot leaves the minimum warmup and
replacement spacing unresolved. The [N=4 L=120 β=0.70 prior pilot](../N4_L120_res/SAMPLING_VALIDATION_RESULTS_20261126.md)
found |ρ(8)| ≤ 0.013 for its charge observables, supporting spacing eight
for that ensemble. The [N=4 L=22 depth comparison](L72_NEAR_SOURCE_RESULTS.md#n4-depth-comparison)
also found that the N=21 near-source scan needed about five times the
expected depth to accumulate 99% of the target weight. The comparisons
vary the lattice size and β as well as N.

Four 200,000-cycle L=72 source chains measured every cycle project to
about 6 h 49 min of simulation wall time. Use those histories to check
burn-in stability in Q_U and Q_U² and compare candidate spacings in the
hundreds to thousands of cycles. The short pilot reports individual
lags through 1,024 cycles. The [L=72 follow-up setup](MCMC_VALIDATION.md)
adds longer lags and spaced late windows for choosing the new initializer.
Then use fixed-cutoff pilots in the weight-bearing region to test
charge decorrelation at each proposal count.

## L=150 next prior run

The four chains on AMD EPYC 7742 span
0.59926–0.60225 s/cycle, with a maximum RSS of 27 MiB per process.
The pilot measured every cycle and included all 50 cooling sweeps at
each measurement. Its median cycle costs 4.91 times as much as the L=72,
β=0.60 run at the same measurement stride. Four 200,000-cycle hot
chains in one allocation project to **33 h 27 min** of simulation wall
time at the measured median rate. The job requests **40 h** under the
96 h time limit for `job_gratis` on `epyc2`. [UBELIX QoS limits](https://hpc-unibe-ch.github.io/runjobs/partitions/#gratis)

From the UBELIX checkout, submit the longer prior pilot with

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
bash N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh L150-prior 200000
```

The timing pilot establishes cost. Use the longer run to inspect
thermalization, charge-sector movement, Q_U and Q_U² autocorrelations,
and block-error stability before selecting live-point spacing and
starting L=150 NS benchmarking. Extend the prior run if its charge
autocorrelation windows or block errors remain unresolved.
