#!/bin/bash
# Submission driver: run with bash on the UBELIX login node.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
(( $# == 0 )) || fail "Usage: bash $0"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
executable=${NS_EXECUTABLE:-$repo/cpn_ns_N4}
[[ $executable == /* && -x $executable ]] || fail 'Build cpn_ns_N4 first or set an absolute NS_EXECUTABLE.'
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'Expected an N=4 executable.'
mkdir -p "$repo/N4_L66_res"
campaign=$(mktemp -d "$repo/N4_L66_res/campaign.XXXXXX")
printf 'job_id\tjob_directory\n' > "$campaign/ns_jobs.tsv"
export NS_SCRATCH="$scratch" NS_EXECUTABLE="$executable" NS_STOC=26136
# Match the L38 doubled-proposal ensemble; keep initialization separately testable.
export NS_INIT_SWEEPS=20 NS_INIT_SPACING=8
unset NS_SEED_BASE
jobs=()
for batch in 1 2 3; do
    id=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=04:00:00 \
        --job-name="ns_L66_2xstoc_$batch" N4_volume_benchmark/run_ubelix.sh 66 110000) ||
        fail "Submission failed; already submitted jobs are recorded in $campaign/ns_jobs.tsv"
    id=${id%%;*}
    [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $id"
    jobs+=("$id")
    printf '%s\t%s\n' "$id" "$scratch/ns_N4_beta0p7_volume_benchmark/L66/job_$id" >> "$campaign/ns_jobs.tsv"
    echo "Submitted $id: four L66 streams, 110000 updates, 26136 proposals/update"
done
dependency=$(IFS=:; echo "${jobs[*]}")
printf -v retry 'sbatch --export=ALL --dependency=afterok:%s N4_volume_benchmark/analyze_L66_ubelix.sh %s %s %s %q' \
    "$dependency" "${jobs[@]}" "$campaign"
printf '%s\n' "$retry" > "$campaign/analyze_command.txt"
analysis=$(sbatch --parsable --export=ALL --dependency="afterok:$dependency" \
    --output="$campaign/slurm_analysis_%j.out" N4_volume_benchmark/analyze_L66_ubelix.sh "${jobs[@]}" "$campaign") ||
    fail "NS jobs submitted; retry analysis using $campaign/analyze_command.txt"
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $analysis"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
echo "Analysis job $analysis; outputs and submission records: $campaign"
