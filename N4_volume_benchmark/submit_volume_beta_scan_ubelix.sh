#!/bin/bash
# Run with bash from the UBELIX login node. This submits analysis jobs only.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
worker="$project_dir/N4_volume_benchmark/volume_beta_scan_ubelix.sh"
export N_BOOTSTRAP="${N_BOOTSTRAP:-200}" BOOTSTRAP_SEED="${BOOTSTRAP_SEED:-20261118}"
export MCMC_BURN_IN="${MCMC_BURN_IN:-20000}" MCMC_BLOCK_SIZE="${MCMC_BLOCK_SIZE:-128}"
export L22_MAX_STREAMS="${L22_MAX_STREAMS:-100}" STREAM_SELECTION_SEED="${STREAM_SELECTION_SEED:-20261118}"
[[ "$N_BOOTSTRAP" =~ ^[0-9]+$ && "$N_BOOTSTRAP" -ge 2 ]] || { echo "N_BOOTSTRAP must be >=2." >&2; exit 1; }
[[ "$BOOTSTRAP_SEED" =~ ^[0-9]+$ ]] || { echo "BOOTSTRAP_SEED must be nonnegative." >&2; exit 1; }
[[ "$MCMC_BURN_IN" =~ ^[0-9]+$ ]] || { echo "MCMC_BURN_IN must be nonnegative." >&2; exit 1; }
[[ "$MCMC_BLOCK_SIZE" =~ ^[0-9]+$ && "$MCMC_BLOCK_SIZE" -ge 1 ]] || { echo "MCMC_BLOCK_SIZE must be positive." >&2; exit 1; }
[[ "$L22_MAX_STREAMS" =~ ^[0-9]+$ && "$L22_MAX_STREAMS" -ge 2 && "$L22_MAX_STREAMS" -le 800 ]] || { echo "L22_MAX_STREAMS must be between 2 and 800." >&2; exit 1; }
[[ "$STREAM_SELECTION_SEED" =~ ^[0-9]+$ ]] || { echo "STREAM_SELECTION_SEED must be nonnegative." >&2; exit 1; }
for path in "${MCMC_L22_DIR:-}" "${MCMC_L38_DIR:-}"; do
    [[ -z "$path" || -d "$path" ]] || { echo "Missing MCMC directory: $path" >&2; exit 1; }
done
mkdir -p "$project_dir/N4_L38_res"
output_dir="$(mktemp -d "$project_dir/N4_L38_res/volume_scan.XXXXXX")"
common=(--parsable --nodes=1 --chdir="$project_dir" --export=ALL)
l22_mem="${L22_SCAN_MEM:-16G}"
l22_time="${L22_SCAN_TIME:-04:00:00}"
l38_mem="${L38_SCAN_MEM:-8G}"
l38_time="${L38_SCAN_TIME:-04:00:00}"
comparison_mem="${COMPARISON_SCAN_MEM:-16G}"
comparison_time="${COMPARISON_SCAN_TIME:-02:00:00}"
printf 'Outputs and submission records: %s\n' "$output_dir"
printf 'stage\tmemory\ttime_limit\nL22\t%s\t%s\nL38\t%s\t%s\ncomparison\t%s\t%s\n' \
    "$l22_mem" "$l22_time" "$l38_mem" "$l38_time" "$comparison_mem" "$comparison_time" \
    | tee "$output_dir/resources.tsv"
printf 'stage\tjob_id\n' > "$output_dir/jobs.tsv"
printf 'N_BOOTSTRAP=%s\nBOOTSTRAP_SEED=%s\nMCMC_BURN_IN=%s\nMCMC_BLOCK_SIZE=%s\nMCMC_L22_DIR=%s\nMCMC_L38_DIR=%s\nVOLUME_DATA_ROOT=%s\n' \
    "$N_BOOTSTRAP" "$BOOTSTRAP_SEED" "$MCMC_BURN_IN" "$MCMC_BLOCK_SIZE" \
    "${MCMC_L22_DIR:-auto-discover}" "${MCMC_L38_DIR:-job_22121710 if present}" \
    "${VOLUME_DATA_ROOT:-/scratch/network/users/lb25v444/out_data}" > "$output_dir/settings.txt"
printf 'L22_MAX_STREAMS=%s\nSTREAM_SELECTION_SEED=%s\n' \
    "$L22_MAX_STREAMS" "$STREAM_SELECTION_SEED" >> "$output_dir/settings.txt"
l22="$(sbatch "${common[@]}" --job-name=N4_L22_betas --mem="$l22_mem" --time="$l22_time" \
    --output="$output_dir/L22_%j.log" "$worker" 22 "$project_dir" "$output_dir")"
l22="${l22%%;*}"
printf 'L22\t%s\n' "$l22" >> "$output_dir/jobs.tsv"
l38="$(sbatch "${common[@]}" --job-name=N4_L38_betas --mem="$l38_mem" --time="$l38_time" \
    --output="$output_dir/L38_%j.log" "$worker" 38 "$project_dir" "$output_dir")"
l38="${l38%%;*}"
printf 'L38\t%s\n' "$l38" >> "$output_dir/jobs.tsv"
comparison="$(sbatch "${common[@]}" --job-name=N4_volume_plot --mem="$comparison_mem" --time="$comparison_time" \
    --dependency="afterok:$l22:$l38" --output="$output_dir/comparison_%j.log" \
    "$worker" compare "$project_dir" "$output_dir")"
comparison="${comparison%%;*}"
printf 'comparison\t%s\n' "$comparison" >> "$output_dir/jobs.tsv"
printf 'L22 analysis (%s streams): %s\nL38 analysis (8664 proposals): %s\nDependent comparison: %s\n' "$L22_MAX_STREAMS" "$l22" "$l38" "$comparison"
printf 'Check: sacct -j %s,%s,%s --format=JobID,State,Elapsed,MaxRSS,ExitCode\n' "$l22" "$l38" "$comparison"
printf 'Final table: %s/volume_comparison.csv\nFinal plot: %s/volume_dependence.png\n' "$output_dir" "$output_dir"
