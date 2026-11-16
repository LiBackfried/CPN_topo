# N=21, L=72 nested-sampling benchmark

16 November 2026

## Timing results

For CP²⁰ at `N=21`, `L=72`, and `beta=0.6`, the updated code was **38.7× faster per NS update** in the matched continuations. At a fresh start the loop was **41.1× faster per update**.

| Starting point | Seed pairs | Updates per trial | Baseline s/update | Updated s/update | Paired loop speedup | Paired process speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Continuation from local UBELIX checkpoints | 3 | 20 | 2.9640 | 0.07495 | **38.7×** (37.1–41.2×) | 37.2× |
| Fresh canonical initialization | 3 | 12 | 2.9414 | 0.07323 | **41.1×** (39.6–42.5×) | 6.1× |

Each time column reports the median across seeds. Each speedup is the median of the three baseline-to-updated ratios computed within the seed pairs. Parentheses give the observed range. Fresh process wall time fell from a median of 41.28 s to 7.08 s. Live-point initialization alone took roughly 6 s of CPU time in both builds, accounting for most of the updated process time in these 12-update trials.

| Starting point | Seed | Baseline s/update | Updated s/update | Loop speedup |
| --- | ---: | ---: | ---: | ---: |
| Continuation | 16774 | 3.0843 | 0.07495 | 41.15× |
| Continuation | 16775 | 2.9640 | 0.07998 | 37.06× |
| Continuation | 16776 | 2.8967 | 0.07493 | 38.66× |
| Fresh | 16774 | 2.8971 | 0.07323 | 39.56× |
| Fresh | 16775 | 2.9414 | 0.06927 | 42.46× |
| Fresh | 16776 | 3.2921 | 0.08001 | 41.14× |

The updated loop accumulates local energy differences, batches full-lattice normalization, and recomputes the full energy near the acceptance threshold and at the end of the batch. The baseline normalized and recomputed the lattice energy after each stochastic proposal under `num_norm=1`. The updated build also removes the first write to the replacement slot and reuses local charge densities in the topology measurements. The measured speedup includes all three changes. [Update kernel](../lib/cpn_update_nestsampl.c), [NS main loop](../src/cpn_ns.c), [Measurements](../lib/cpn_meas.c)

All trials produced the expected number of update, measurement, and cooling rows. Action-density cutoffs decreased throughout each trial. The recorded `z` and `U` acceptance fractions matched at every paired step. The largest paired action-density difference was `2.45e-12` across continuations and `1.72e-12` across fresh starts. Continuations started at action-density cutoffs from 0.82656 to 0.82737, with mean `z` acceptance of 91.0–91.9% and mean `U` acceptance of 98.75–98.87%. The figures cover these short trajectories on the local machine. UBELIX wall time and later NS depths remain unmeasured for this comparison.

## Method

- The baseline was `5428e2b`, the pre-optimization revision used in the N=4 timing campaign. It has the same per-proposal full-lattice normalization and energy recomputation as the September production launcher revision `71531f4`, with the October energy-preservation checks. The updated revision was `37d1e55`, the checkout tip at the time of the benchmark. The executable banners verified compile-time `N=21` for both builds.
- Used the local AMD Ryzen 7 8845HS, Ubuntu 24.04 under WSL2, GCC 13.3.0, and the repository's `-O3` flags. Runs were sequential and pinned to logical CPU 8. Working files and configuration I/O lived on WSL's ext4 filesystem. Both binaries used the configure fallback with MD5 disabled because WSL lacked the OpenSSL development headers.
- The N=21 production inputs specify a `72 × 72` lattice, beta `0.6`, theta `0`, 50 live points, 5,000 stochastic proposals per NS update, four microcanonical sweeps, `num_norm=1`, and 50 cooling sweeps with measurements every five sweeps. The fresh runs used 20 heatbath initialization sweeps and eight sweeps between live points. Each fresh pair shared one RNG seed. Each continuation pair restored the same live configurations, energies, and RNG state.
- Both builds used the same `CLOCK_MONOTONIC` probe at the NS loop boundaries. Loop wall time includes proposal generation, microcanonical sweeps, cooling, observable measurements, and writes during each update. Live-point initialization and the first measurement occur before the timed loop. Process wall time includes initialization, the first measurement, and shutdown, with checkpoint copying done before the process starts.

### Checkpoint preparation

The first continuation pilot exposed an inconsistency between one saved configuration and its energy table. The audit verified all 500 stored MD5 hashes and recomputed all 500 energies across the ten local `out_data_ubelix` snapshots. Each snapshot had exactly one energy mismatch. The table's maximum-energy slot contained a byte-for-byte duplicate of another live slot. This is consistent with the baseline loop writing a proposal into that slot before completing the NS update. [Checkpoint audit](results/checkpoint_audit.csv)

The timed continuation pairs used `run_0`, `run_1`, and `run_2`, with last saved acceptance labels 3974, 3922, and 3973. For each, one untimed update with the updated binary replaced the inconsistent slot on a private copy. This update used the saved cutoff and RNG state. The NS loop excludes the maximum-energy slot from proposal selection. After the replacement, the 50 recomputed energies in each copied checkpoint matched its energy table exactly, and only the replaced slot's table entry had changed. Both timing variants resumed from identical copies of the resulting checkpoint.

## Reproduce

Run from the repository root in Ubuntu-24.04 WSL, with the local checkpoints available under `out_data_ubelix` and the two revisions available in Git. Choose a new output directory for each campaign.

```bash
python3 N21_L72_benchmark_20261116/benchmark.py \
    N21_L72_benchmark_20261116/repeat --cpu 8 --resume-updates 20 --fresh-updates 12
```

The [timings CSV](results/timings.csv) has the per-trial timings and cutoff and acceptance summaries. Each trial directory under `results/` contains the exact input, stdout/stderr, and measurement outputs. The executable banners, build logs, and environment metadata are also saved there.
