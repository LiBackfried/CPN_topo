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
- Bootstrap whole independently seeded streams with replacement, not individual dead points. Each replicate must re-merge by energy and recompute weights; this preserves within-stream correlations. Report the sample standard deviation across replicates as the bootstrap error.
- Raw bootstrap replicates are opt-in via `--save-bootstrap-samples`. Normal output is `summary.txt`, `results.json`, and four PNG plots.
- Example local invocation:

  ```bash
  python analyze_nested_sampling.py RUN_ROOT [RUN_ROOT ...] \
      --output analysis_results/example \
      --bootstrap 1000 --seed 1234
  ```

- The ready UBELIX analysis wrapper is `sh_files/analyze_4x5000_ubelix.sh`. It resolves Python to an absolute path before `srun`, because a bare `python` command may disappear in the compute-task environment. Its defaults analyze the four known N=21 job folders, use 500 bootstrap replicates, and write to a job-specific directory under `analysis_results/` in the checkout.

## Verification checklist

- For config changes, verify the expected run count, distinct seeds, lattice/beta, `num_live_pts`, stochastic-update count, fresh/resume flags, and the `num_ns_meas - 1` update count.
- For shell changes, run `bash -n` and retain preflight checks before launching `srun`.
- For Python changes, run `python -m py_compile analyze_nested_sampling.py utils/nest_sampl.py` and a small analysis against available local sample data. Remove smoke-test outputs afterward.
- Check `git diff --check` and `git status --short`; preserve unrelated user changes and generated data.
