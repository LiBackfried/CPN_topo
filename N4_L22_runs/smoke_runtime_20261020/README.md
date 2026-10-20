# N=21, L=72 versus N=4, L=22 runtime smoke test

Run locally in Ubuntu 24.04 under WSL on 2026-10-20. Both executables were
built from the same source with GCC 13.3.0 and `-O3`. The saved binaries report
their compiled values as `N=21` and `N=4`, respectively.

## Matched workload

The inputs match the latest fresh UBELIX production job except for the short
smoke-test length and, in the second case, the requested lattice/model size:

- one chain and one CPU thread
- beta 0.6, identical seed 46774
- 50 live points
- 4 microcanonical sweeps per NS update
- 15,500 stochastic updates per NS update
- `num_norm=1`
- 5 NS updates (`num_ns_meas=6`, including the initial measurement)

The runs and their output files lived on WSL's Linux filesystem while timing,
so Windows-mounted filesystem I/O is not included in the measured workload.
The host CPU was an AMD Ryzen 7 8845HS (8 cores/16 threads); each process was
single-threaded.

## Results

| Run | N=21, L=72 simulation | N=4, L=22 simulation | Loop speedup | Total wall speedup |
|---:|---:|---:|---:|---:|
| 1 | 54.197472 s | 1.249109 s | 43.39x | 40.10x |
| 2 | 53.591523 s | 1.205797 s | 44.44x | 40.40x |
| Mean | 53.894498 s | 1.227453 s | **43.91x** | **40.25x** |

Mean time per NS update fell from 10.778900 s to 0.245491 s. The measured
43.91x improvement in the nested-sampling loop is 2.43% below the expected
45x and therefore supports the expected speedup. At fixed compute time, this
predicts roughly 44 times as many NS updates. Initialization improves less
(27.99x on the mean), which explains the lower end-to-end wall speedup for
this deliberately short run.

`benchmark_summary.csv` contains both observations. The `results_*` folders
contain the persisted raw timing, stdout/stderr, program log, and acceptance
rates from run 2. The large live-configuration files were intentionally not
copied from WSL.
