#!/bin/bash
# Run with bash from the UBELIX login node. This submits analysis jobs only.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
worker="$project_dir/N4_volume_benchmark/volume_beta_scan_ubelix.sh"
export N_BOOTSTRAP="${N_BOOTSTRAP:-200}" BOOTSTRAP_SEED="${BOOTSTRAP_SEED:-20261118}"
export MCMC_BURN_IN="${MCMC_BURN_IN:-20000}" MCMC_BLOCK_SIZE="${MCMC_BLOCK_SIZE:-128}"
[[ "$N_BOOTSTRAP" =~ ^[0-9]+$ && "$N_BOOTSTRAP" -ge 2 ]] || { echo "N_BOOTSTRAP must be >=2." >&2; exit 1; }
[[ "$BOOTSTRAP_SEED" =~ ^[0-9]+$ ]] || { echo "BOOTSTRAP_SEED must be nonnegative." >&2; exit 1; }
[[ "$MCMC_BURN_IN" =~ ^[0-9]+$ ]] || { echo "MCMC_BURN_IN must be nonnegative." >&2; exit 1; }
[[ "$MCMC_BLOCK_SIZE" =~ ^[0-9]+$ && "$MCMC_BLOCK_SIZE" -ge 1 ]] || { echo "MCMC_BLOCK_SIZE must be positive." >&2; exit 1; }
for path in "${MCMC_L22_DIR:-}" "${MCMC_L38_DIR:-}"; do
    [[ -z "$path" || -d "$path" ]] || { echo "Missing MCMC directory: $path" >&2; exit 1; }
done
mkdir -p "$project_dir/N4_L38_res"
output_dir="$(mktemp -d "$project_dir/N4_L38_res/volume_scan.XXXXXX")"
common=(--parsable --chdir="$project_dir" --export=ALL)
printf 'Outputs and submission records: %s\n' "$output_dir"
printf 'stage\tjob_id\n' > "$output_dir/jobs.tsv"
printf 'N_BOOTSTRAP=%s\nBOOTSTRAP_SEED=%s\nMCMC_BURN_IN=%s\nMCMC_BLOCK_SIZE=%s\nMCMC_L22_DIR=%s\nMCMC_L38_DIR=%s\nVOLUME_DATA_ROOT=%s\n' \
    "$N_BOOTSTRAP" "$BOOTSTRAP_SEED" "$MCMC_BURN_IN" "$MCMC_BLOCK_SIZE" \
    "${MCMC_L22_DIR:-auto-discover}" "${MCMC_L38_DIR:-job_22121710 if present}" \
    "${VOLUME_DATA_ROOT:-/scratch/network/users/lb25v444/out_data}" > "$output_dir/settings.txt"
l22="$(sbatch "${common[@]}" --job-name=N4_L22_betas --mem=64G --time="${L22_SCAN_TIME:-24:00:00}" \
    --output="$output_dir/L22_%j.log" "$worker" 22 "$project_dir" "$output_dir")"
l22="${l22%%;*}"
printf 'L22\t%s\n' "$l22" >> "$output_dir/jobs.tsv"
l38="$(sbatch "${common[@]}" --job-name=N4_L38_betas --mem=8G --time="${L38_SCAN_TIME:-04:00:00}" \
    --output="$output_dir/L38_%j.log" "$worker" 38 "$project_dir" "$output_dir")"
l38="${l38%%;*}"
printf 'L38\t%s\n' "$l38" >> "$output_dir/jobs.tsv"
comparison="$(sbatch "${common[@]}" --job-name=N4_volume_plot --mem=16G --time=02:00:00 \
    --dependency="afterok:$l22:$l38" --output="$output_dir/comparison_%j.log" \
    "$worker" compare "$project_dir" "$output_dir")"
comparison="${comparison%%;*}"
printf 'comparison\t%s\n' "$comparison" >> "$output_dir/jobs.tsv"
printf 'L22 analysis: %s\nL38 analysis (8664 proposals): %s\nDependent comparison: %s\n' "$l22" "$l38" "$comparison"
printf 'Check: sacct -j %s,%s,%s --format=JobID,State,Elapsed,MaxRSS,ExitCode\n' "$l22" "$l38" "$comparison"
printf 'Final table: %s/volume_comparison.csv\nFinal plot: %s/volume_dependence.png\n' "$output_dir" "$output_dir"
