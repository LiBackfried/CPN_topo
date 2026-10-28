# CPN_topo working notes

This repository contains C code for CP(N-1) simulations, stochastic nested sampling, UBELIX/Slurm launchers, and Python analysis. The points below summarize the durable conclusions from recent work in this project.

## Repository layout

- `src/`, `lib/`, and `include/` contain the simulation code. `cpn_ns` is the nested-sampling executable; `cpn` is the regular MCMC executable.
- `include/macro.h` defines `N` at compile time. The checked-in value is currently `N=21`.
- `config_files/` contains the N=21 production and continuation inputs.
- `sh_files/` contains the current N=21 UBELIX job scripts. Some older per-run READMEs still show the scripts at repository root; use the copies in `sh_files/`.
- `N4_L22_runs/` contains the CP^3 (`N=4`), L=22 setup and the saved runtime benchmark.
- `analyze_nested_sampling.py` and `utils/nest_sampl.py` implement command-line analysis and stream-level bootstrap errors.
- Generated simulation output (`out_data*`) and `analysis_results/` are intentionally ignored by Git.

## Build conventions

- Bootstrap Autotools files with `bash script_build_code.sh` when required.
- For local compilation from Windows, explicitly use the `Ubuntu-24.04` WSL distribution, which provides GCC and Make: `wsl.exe --distribution Ubuntu-24.04 -- bash -lc 'cd /mnt/c/Liane/00_Doktorat/PhD_projects/CPN_NestSamp/CPN_topo && make cpn_ns'`. Do not rely on the default `wsl.exe` distribution; the default `Ubuntu` instance may not expose the compiler toolchain.
- On UBELIX, `bash script_compile_code_ubelix.sh <N> [target]` changes `include/macro.h` and compiles. For example, `bash script_compile_code_ubelix.sh 21 cpn_ns`.
- Treat `N` as part of the executable, not an input-file parameter. Before a run, verify that the executable was compiled for the intended `N`; invoking `cpn_ns` without a config prints its compiled value.
- The N=4 helper at `N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/build_cpn_ns_N4_ubelix.sh` creates `cpn_ns_N4`, verifies it, and restores the pre-existing `include/macro.h` and `cpn_ns`. Preserve that restoration behavior when changing the helper.
- Keep UBELIX shell scripts and config files LF-only. Validate edited launchers with `bash -n` (Git Bash or WSL is sufficient locally).

## Nested-sampling parameter semantics

- `num_ns_meas` includes the initial measurement. The loop performs `num_ns_meas - 1` nested-sampling updates. Thus 5,000 updates require `num_ns_meas 5001`, 4,500 require `4501`, and 50,000 require `50001`.
- A useful stochastic-update baseline is approximately `3 * L^2`, reflecting the three update types. The N=4, L=22 production setup therefore uses 1,500 updates (close to 1,452).
- Each independent chain must have a distinct positive RNG seed.
- Give every chain its own working directory. The executable writes files such as `acceptance_rate.dat` through relative paths, so sharing a working directory mixes or overwrites results.
- Fresh runs use `start 1` and `rng_start 0`. Resume runs use `start 2` and `rng_start 1` and must point to an existing checkpoint directory.
- A continuation repeats the initial checkpoint measurement and resets acceptance-rate iteration labels to 1. Account for both when joining run segments.

## UBELIX/Slurm rules

- Submit job files with `sbatch`; do not run them with `bash` or `./script`. This remains true inside an Open OnDemand/code-server allocation: `SLURM_JOB_ID` may already be set there, but that allocation may not contain the ten CPUs requested by an internal `srun`.
- Ten-chain jobs use ten single-threaded Slurm tasks (`--ntasks=10`, `--cpus-per-task=1`), one chain per `SLURM_PROCID`.
- After submission, check the new batch allocation with `sacct`/`scontrol`; a ten-chain job should have ten requested/allocated CPUs. “More processors requested than permitted” usually means the script was executed inside a smaller parent allocation or submission options overrode the file.
- Production output belongs on scratch under `/scratch/network/users/lb25v444/out_data/<run_group>/job_<JOB_ID>/run_<0..9>/`. Fresh submissions should use a new job-specific directory and avoid overwriting prior output.
- Resume jobs update checkpoint files in place. Before starting any chain, validate all expected live configurations plus `live_energy.dat` and `rng_state.dat`. Never run two continuations against the same checkpoint data simultaneously.
- Local work normally prepares and validates scripts only. Do not imply that a job was submitted or remote data changed unless that actually happened.

## Current run families

- The established N=21 production family is L=72, beta=0.6, 50 live points, and 5,000 stochastic updates per NS step. Its four ten-stream datasets use job IDs `15484566`, `15985454`, `16235818`, and `16236075`; the matching launchers and configs now represent continuation workflows, so read their adjacent READMEs before editing or submitting.
- The smaller production candidate is `N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/`: N=4, L=22, beta=0.7, 50 live points, 1,500 stochastic updates, and 50,000 NS updates per chain.
- The saved matched smoke test in `N4_L22_runs/smoke_runtime_20261020/` measured a 43.91x mean nested-sampling-loop speedup for N=4, L=22 versus N=21, L=72 (5 updates, two repetitions), supporting a planning factor of roughly 44 rather than assuming an exact value.

## Analysis conventions

- `analyze_nested_sampling.py` accepts either individual run directories or parent directories whose immediate `run0`/`run_0`-style children contain `dati.dat`, `topo.dat`, and `input.conf`.
- Combine independent streams by sorting all dead points in decreasing energy. The effective live-point count is the sum of the selected streams' `num_live_pts` values.
- Never compare an unweighted mean of nested-sampling dead points with regular MCMC. Use the nested-sampling weights. Before presenting a formal canonical comparison, also confirm that the configured `beta` and live-point initialization match the intended prior/reweighting convention.
- The current nested-sampling prior is already the normalized canonical ensemble at the configured source `beta`; no separate likelihood factor is applied at that same beta. The primary source-coverage output is `log_accumulated_prior_mass`, normally approximately zero. `log_Z` is retained only as a deprecated compatibility alias and is not the physical canonical partition function.
- `dati.dat[:,1]` is the intensive action density `epsilon = S_beta / (2 * beta * N * V)`. The beta-independent extensive energy is `H = 2 * N * V * epsilon`, and the dimensionless Symanzik action is `S_beta = beta * H`. The Python observable named `energy` is currently `2 * epsilon`, so equivalently `H = N * V * energy` when the default action prefactor is used.
- Reweighting changes beta only. For source `beta_0` and target `beta_1`, add `-(beta_1 - beta_0) * H` to each log quadrature weight. Theta and all other action parameters remain fixed; the analysis rejects mixed source betas or mixed theta values.
- `N` is not stored in `input.conf` and cannot be inferred safely from the output data. Pass the executable's compile-time value with `--cpn-n N`; `--cpn-n` is mandatory with `--target-beta`. When supplied, the output includes `mean_extensive_energy` and `mean_symanzik_action`.
- The analysis reports `log_remaining_prior_mass = log(X_final)` and `remaining_prior_mass = X_final` using the expected-shrinkage convention. Use the logarithmic value when the linear remainder underflows. Together, the accumulated and remaining source-prior masses should sum to one up to quadrature round-off.
- Beta-reweighted output reports `log_Z_ratio = log[Z(beta_target) / Z(beta_source)]` separately from the source-prior coverage fields. It also reports `quadrature_effective_sample_size`; this measures concentration of deterministic quadrature weights and is not a count of independent Markov-chain samples.
- Weight normalization and positive log means use log-sum-exp. Ordinary weighted sums retain representable linear products for cancellation accuracy and recover only underflowed products in signed log space. Compute variances from centered observations, as done for the topological susceptibility, rather than by subtracting two large moments.
- Bootstrap whole independently seeded streams with replacement, not individual dead points. Each replicate must re-merge by energy and recompute weights; this preserves within-stream correlations. Report the sample standard deviation across replicates as the bootstrap error.
- Raw bootstrap replicates are opt-in via `--save-bootstrap-samples`. Normal output is `summary.txt`, `results.json`, and four PNG plots.
- Example local invocation:

  ```bash
  python analyze_nested_sampling.py RUN_ROOT [RUN_ROOT ...] \
      --output analysis_results/example \
      --bootstrap 1000 --seed 1234
  ```

- Example beta-only reweighting invocation:

  ```bash
  python analyze_nested_sampling.py RUN_ROOT [RUN_ROOT ...] \
      --output analysis_results/reweighted \
      --bootstrap 1000 --seed 1234 \
      --cpn-n 21 --target-beta 0.6001
  ```

- The analysis requires NumPy, SciPy, and Matplotlib. The UBELIX wrappers load `SciPy-bundle` and explicitly verify all three imports.
- The ready UBELIX analysis wrappers are `sh_files/analyze_4x5000_ubelix.sh` for N=21 and `sh_files/analyze_N4_L22_ubelix.sh` for N=4. They pass their known compile-time `N`, resolve Python to an absolute path before `srun`, and accept an optional `TARGET_BETA` environment variable for beta-only reweighting. For example, `TARGET_BETA=0.6001 sbatch sh_files/analyze_4x5000_ubelix.sh`.

## Verification checklist

- For config changes, verify the expected run count, distinct seeds, lattice/beta, `num_live_pts`, stochastic-update count, fresh/resume flags, and the `num_ns_meas - 1` update count.
- For shell changes, run `bash -n` and retain preflight checks before launching `srun`.
- For local Python verification on Windows, use the `fpaction2` Conda environment. If `conda` is not on `PATH`, invoke `C:\Users\libac\miniconda3\Scripts\conda.exe run -n fpaction2 python ...`.
- For Python changes, run `python -m py_compile analyze_nested_sampling.py utils/nest_sampl.py tests/test_nest_sampl.py`, run `python -m unittest discover -s tests -v`, and perform a small analysis against available local sample data. For beta-reweighting changes, also exercise `--cpn-n` plus a nearby `--target-beta` and a small stream bootstrap. Remove smoke-test outputs afterward.
- Check `git diff --check` and `git status --short`; preserve unrelated user changes and generated data.
