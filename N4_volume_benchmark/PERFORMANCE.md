# CP³ nested-sampling kernel timings

## Measured wall time

Ubuntu-24.04 WSL, GCC 13.3, `-O3`, one pinned logical CPU on an AMD Ryzen 7
8845HS. Both N=4 builds used isolated source trees and the same compiler
settings. The WSL builds used the configure fallback without MD5. Timers in
the benchmark builds used `CLOCK_MONOTONIC` around the NS loop and around each
I/O and measurement phase. Loop times exclude live-point initialization and
its first measurement. Configuration I/O used the WSL Linux filesystem.

Each pilot used 100 updates, beta 0.7, theta 0, 50 live points, four
microcanonical sweeps, `num_norm=1`, 50 cooling sweeps measured every five,
and the benchmark's volume-dependent proposal counts. Initialization used
20 burn-in steps and a live-point spacing of eight steps. The first two rows
are medians over seeds 70421, 70423 and 70427. The three larger optimized
pilots each used seed 70421.

| L | Baseline ms/update | Incremental energy | Also remove first write | Also reuse charge densities | Measured speedup |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 22 | 27.30 | 3.82 | 3.30 | 2.75 | 9.93× |
| 38 | 220.41 | 11.06 | 9.26 | 7.72 | 28.55× |
| 66 | — | — | — | 25.26 | — |
| 90 | — | — | — | 51.37 | — |
| 120 | — | — | — | 101.79 | — |

An `L^4` baseline extrapolation anchored to the measured L=38 time gives
2.01, 6.94, and 21.92 s/update at L=66, 90, and 120. Dividing by the measured
optimized times gives projected speedups of about 79×, 135×, and 215× on the
local timing model. These ratios depend on the baseline's cache and memory
scaling. Cluster timings also depend on CPU and scratch I/O.

| L | First slot write, kernel-only | Observables before density reuse | Observables after density reuse | Remaining config and checkpoint I/O |
| ---: | ---: | ---: | ---: | ---: |
| 22 | 0.23 | 1.96 | 1.46 | 0.51 |
| 38 | 0.47 | 5.77 | 4.31 | 1.12 |
| 66 | — | — | 14.06 | 3.02 |
| 90 | — | — | 30.35 | 5.17 |
| 120 | — | — | 55.39 | 8.36 |

Phase values are ms/update. Config and checkpoint I/O includes two live
reads, the final replacement write, and the live-energy and RNG writes.
Observable time includes cooling and measurement-file output. At L=22 and
38 the density reuse saved about 25% of observable time. The first slot
write stored the unmodified proposal, which the verified replacement
overwrote before the next read. Both changes gave byte-identical output and
checkpoints relative to the kernel-only build across the matched runs.

## Constrained update and verification

Each accepted heatbath proposal adds its local Symanzik energy difference
divided by the volume. The single-field heatbath routines already normalize
their results. The batch coalesces scheduled full-lattice normalizations
into one before writing the replacement. Full energy calculations bracket
the microcanonical sweeps and verify the energy and strict cutoff at the
end of the batch. The acceptance threshold remains `E_dead - 1e-9`, with a
strict comparison. Within the roundoff guard the code evaluates the full
energy of the proposed configuration before deciding.

- An audit build compared the incremental trial energy with a fresh
  full-lattice evaluation for all 150,000 proposals at L=22 and 433,200 at
  L=38. Every error was within the guard, and every decision matched the
  full-energy decision. The logged discrepancies were at most `8.6e-15`
  and `1.2e-14`, against guards of `4.90e-12` and `1.33e-11`. None of the
  naturally sampled proposals in the logged ranges needed the fallback.
- `tests/test_ns_energy.c` deliberately places a site and both link
  directions at the cutoff and on either side of the tolerated threshold.
  With the running energy biased towards the opposite decision near the
  threshold, the tests verified rejection at equality, acceptance one ULP
  below, and byte-for-byte restoration of the rejected configuration with
  the running energy unchanged. The test passed at L=22 and L=38.
- In the optimized build, a fresh 37-update segment plus a 63-update
  continuation reproduced the 100-update uninterrupted run at L=22 and
  L=38. The 50 live configurations, live energies, RNG state, and joined
  measurements matched byte for byte after removing the repeated boundary
  measurement and renumbering the continuation's acceptance rows.

Matched-seed trajectories can diverge once the two kernels round the fields
differently. Across 12 independent seed pairs at L=22 and seven at L=38,
the following are optimized minus baseline means with paired standard
errors. Each chain contributes one summary of its first 100 dead points.
Topology uses the rounded geometric charges at cooling step 50. These
unweighted dead-point summaries are regression diagnostics.

| Quantity | L=22 | L=38 |
| --- | ---: | ---: |
| Mean dead-point action density | +5.2e-8 ± 1.5e-5 | +2.6e-6 ± 3.1e-5 |
| Final dead-point action density | +2.68e-4 ± 2.35e-4 | +1.54e-4 ± 1.58e-4 |
| z acceptance, percentage points | −0.050 ± 0.031 | +0.037 ± 0.033 |
| U acceptance, percentage points | −0.017 ± 0.009 | +0.026 ± 0.009 |
| Mean geometric Q (U) | −0.026 ± 0.020 | +0.026 ± 0.031 |
| Mean geometric Q (z) | −0.026 ± 0.020 | +0.024 ± 0.028 |
| Mean geometric Q² (U) | −0.048 ± 0.033 | +0.003 ± 0.119 |
| Mean geometric Q² (z) | −0.048 ± 0.033 | −0.001 ± 0.116 |

The L=38 U-acceptance shift is about three paired standard errors. Its
absolute size is 0.026 percentage points, and the proposal audit directly
checked cutoff decisions on the optimized configurations. The pilots
cover early NS depth, where the mean z and U acceptances are above 98%.

For a deeper check at L=22, both builds continued the same two checkpoints
after 5,000 optimized updates. Over the following 100 updates per seed,
mean z acceptance was 73.4% and 74.8%, and mean U acceptance was 90.8% and
91.2%. The means matched between builds to the precision of the output.
Both continuations reached a cutoff below 0.60, with final cutoff
differences of at most `1.5e-10`.

## UBELIX timing

From a UBELIX login node, open the checkout containing the optimized C
sources and run the timing script. It snapshots the current working-tree
sources, builds N=4 executables in isolated scratch directories, and submits
four-chain jobs at 200 and 2,000 updates. It times the updated kernel at all
five volumes and the original kernel at L=22 and L=38.

```bash
bash N4_volume_benchmark/time_ubelix.sh
```

Pass `--updated-only` to measure the updated executable alone. The script
prints the absolute path to the campaign's `jobs.tsv` and the report command.
After the jobs complete, run that command to get median wall seconds per
update for each volume, build, and CPU model.

```bash
bash N4_volume_benchmark/time_ubelix.sh report /path/to/cpn_ns_timing.XXXXXX/jobs.tsv
```

Each task uses the same seed at both lengths and across the two builds. The
report pairs the short and long runs of each task on the same CPU model,
then takes the median of `(elapsed_long - elapsed_short) / 1800`. This
approximately removes initialization. Use longer segments near the desired
cutoff to check the time budget for production.
