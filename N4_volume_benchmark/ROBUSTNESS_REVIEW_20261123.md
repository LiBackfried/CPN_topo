# L90/L120 robustness results, reviewed 2026-11-23

Both pulled robustness analyses are complete locally: L90 **22974797** and
L120 **22974798**. The pooled L90 conditional Gk discrepancy survives the
bin/block grid and every single-stream omission. The pooled L120 comparison
does not exceed the joint 95% threshold in any tested configuration. However,
the four-stream groups flag local residuals at both volumes, so these results
do not establish unbiased prior initialization or constrained sampling.

## Completion and provenance

Reviewed the copied `robustness_steps12_22974797/` and
`robustness_steps12_22974798/` directories and their adjacent submission and
run records. Each analysis and record directory has a `completed` marker.
Both copied Slurm `.err` files are empty; Slurm `.out` files are absent from
the local copies. Remote `sacct` status and raw simulation histories were
not independently inspected.

Each volume contains all nine grid comparisons and three group comparisons,
including tables, plots, covariances, joint diagnostics and simultaneous
intervals. There are 96 observable rows, 768 leave-one-out bin rows and 210
group-pair rows per volume. All 24 comparison covariance matrices are finite,
symmetric and positive semidefinite; their diagonals match the saved squared
residual errors. Recomputed maximum standardized residuals match `joint.json`.
All eight locally available analysis source files match the saved SHA256
hashes at each volume.

L90 uses NS leaves 22810844/22810845/22810846 at 210k updates and MCMC
22635137 at beta=0.95. L120 uses leaves 22885157/22904262/22904264 at 300k
and MCMC 22780263 at beta=1.0. Each has twelve distinct positive NS seeds,
50 live points per stream and source beta=0.7. Settings are the expected
20,000-MC-step cut, bins 8/16/32, blocks 128/512/1024 measurements, 200
whole-stream bootstrap draws, 1,000 joint draws and seed 20261121.
Resolved input paths use `/rs_scratch/users/...`; submission records retain
the original `/scratch/network/users/...` paths.

## Step 1: bin and block choices

At the fixed 512-measurement reference block, the results are:

| Volume | Bins | Largest marginal absolute residual / SE | Component | Approximate joint p |
| --- | ---: | ---: | --- | ---: |
| L90 | 8 | 3.704 | Gk | 0.003996 |
| L90 | 16 | 6.750 | Gk | 0.000999 |
| L90 | 32 | 4.694 | Gk | 0.000999 |
| L120 | 8 | 1.906 | Gk | 0.486513 |
| L120 | 16 | 2.299 | G0 | 0.363636 |
| L120 | 32 | 3.046 | G0 | 0.084915 |

Sources: [L90 grid](../N4_L90_res/robustness_steps12_22974797/step1/grid.csv)
and [L120 grid](../N4_L120_res/robustness_steps12_22974798/step1/grid.csv).
The joint diagnostic maximizes over both correlators and all bins within
one configuration and preserves estimated correlations. It is not an
omnibus test over the nine correlated grid rows.

**L90:** increasing the block from 128 to 1024 does not remove the discrepancy.
Max residual ranges are 3.665-3.713, 6.690-6.806 and 4.687-4.707 for 8/16/32
bins respectively. Eight-bin p is 0.0020-0.0040; 16/32-bin values are at the
simulation resolution floor, 1/1001. These are approximate bootstrap
diagnostics, not Gaussian significance assignments.

At 16 bins/block512, epsilon **0.5756565688-0.5761963290** gives
Gk(NS)-Gk(MCMC) = **+9.42669 +/- 1.39649**. NS and MCMC contribute 1.17998
and 0.746887 to that SE. At 32 bins, bin14 over 0.5759305562-0.5761963290
gives **+12.42434 +/- 2.64690**. Positive and negative conditional offsets
can cancel in integrated observables. This identifies a discrepancy under
the present error model; it does not identify its cause.

**L120:** eight-bin p is 0.465-0.487, 16-bin p is 0.354-0.364 and 32-bin p
is 0.085-0.093. The largest 32-bin G0 residual remains visible:
**-24.68157 +/- 8.10180** over epsilon **0.5404183878-0.5406421418** at
block512. Its standardized magnitude 3.046 is below the simultaneous 95%
critical value 3.195. The pooled check does not reject the conditional
comparison at 5%; this does not establish absence of sampling bias.

Full NS central values equal the preceding twelve-stream analyses.
Changes in SEs reflect a different 200-draw bootstrap seed; MCMC central
values shift slightly as longer blocks discard different incomplete tails.
The previously highlighted L120 bin has not physically disappeared.

## Step 2: groups and single-stream influence

Omission changes below are descriptive shifts divided by the **full NS
bootstrap SE**, not independent significance tests. Each eleven-stream
subset is re-merged with 550 live points at fixed common support.

| Observable | Largest absolute omission shift, L90 | L120 |
| --- | ---: | ---: |
| Action density | 0.488 | 0.464 |
| xi_L_squared | 0.684 | 0.487 |
| Topological susceptibility | 0.697 | 0.804 |
| log_Z_ratio | 0.770 | 0.586 |
| G0 | 0.582 | 0.613 |
| Gk | 0.597 | 0.569 |

Full-ensemble integrated NS/MCMC differences remain at most 0.63 combined
SE for L90 and 1.32 for L120. No single omission dominates these integrated
estimates. For L90's problematic 32-bin Gk bin, every omitted-stream residual
stays positive, **+11.4594 to +13.9796**, compared with +12.4243 for full12.
L120's highlighted G0 residual remains negative, **-29.2344 to -20.9074**.
Maximum omission shifts across all conditional bins are 0.892 full NS SE
at L90 and 0.907 at L120. There is no basis here to discard a particular seed.

At 32 bins/block512, the independent four-stream groups give:

| Volume | Group1 p (max absolute residual / SE) | Group2 | Group3 |
| --- | --- | --- | --- |
| L90 | 0.000999 (6.255) | 0.008991 (3.597) | 0.000999 (7.514) |
| L120 | 0.000999 (5.940) | 0.000999 (4.858) | 0.000999 (5.586) |

Worst bins differ among groups: L90 Gk bins21/1/25; L120 Gk bin12, G0 bin10,
Gk bin10. These are not three independent replications of the same localized
full12 residual. Pairwise integrated differences reach 2.33 combined NS SE
at L90 (groups1-3 action) and 2.17 at L120 (groups2-3 G0), before adjustment
for searching the tables. Sources: each volume's `step2/observables.csv`,
`group_pairs.csv`, `leave_one_out_bins.csv` and group `joint.json` files.

The group checks expose local variability and/or limitations of the
four-stream bootstrap error model, whose tails have weak calibration.
They prevent treating pooled L120 as complete validation; they do not alone
prove bias or identify a faulty stream.

## Next priorities

Retain all twelve production streams per volume. These results do not call
for more production depth or justify excluding a seed. Prioritize beta=0.7
hot/cold-start thermalization and live-point-spacing pilots, plus retrospective
autocorrelation and burn-in diagnostics for target MCMC. Neither is supplied
by these robustness jobs.

For L90, follow with separately seeded validation ensembles testing longer
source equilibration/spacing and increased constrained proposals, keeping
settings changes separate so their effects can be assessed. The findings
do not distinguish initialization, constrained mixing, MCMC limitations or
error-model inadequacy. L120 should share the validation checks despite its
less concerning pooled grid. More bootstrap replicates can check numerical
stability but cannot replace independent streams or establish correct
sampling. Fixed estimated edges, only twelve independent NS streams and
200 NS bootstrap draws limit interpretation of all joint p values.
