#!/bin/bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

more=0
if [[ $# == 1 && $1 == --more ]]; then
    more=1
else
    (( $# == 0 )) || fail "Usage: bash $0 [--more]"
fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this script on UBELIX.'

scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
base="$scratch/ns_N4_beta0p7_volume_benchmark/L38"
original="$base/job_22120845"
[[ -f "$original/completed" && -x "$original/cpn_ns_N4" ]] ||
    fail "Expected the completed original job and its executable in $original"
if (( more )); then
    for id in 22320950 22320951 22320952 22133588 22133589 22133590; do
        [[ -f "$base/job_$id/completed" ]] || fail "Expected completed job $base/job_$id"
    done
    [[ -f "$scratch/mcmc_38_N4_beta1p0_3x100k/job_22121710/completed" ]] || fail 'Expected completed MCMC job 22121710.'
    mkdir -p "$repo/N4_L38_res"
    campaign=$(mktemp -d "$repo/N4_L38_res/extra8664.XXXXXX")
    printf 'job_id\tjob_directory\n' > "$campaign/new_jobs.tsv"
    echo "Analysis and submission records: $campaign"
fi

export NS_SCRATCH="$scratch"
export NS_EXECUTABLE="$original/cpn_ns_N4"
export NS_STOC=8664
unset NS_SEED_BASE NS_INIT_SWEEPS NS_INIT_SPACING

jobs=()
job_ids=()
for batch in 1 2 3; do
    job=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=00:45:00 \
        --job-name="ns_L38_2xstoc_$batch" N4_volume_benchmark/run_ubelix.sh 38 35000) ||
        fail "Submission $batch failed. Jobs printed above were already submitted."
    job=${job%%;*}
    [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $job"
    jobs+=("$base/job_$job")
    job_ids+=("$job")
    if (( more )); then printf '%s\t%s\n' "$job" "$base/job_$job" >> "$campaign/new_jobs.tsv"; fi
    echo "Submitted job $job (4 chains, NS_STOC=$NS_STOC): $base/job_$job"
done

if (( more )); then
    dependency=$(IFS=:; echo "${job_ids[*]}")
    printf -v command 'sbatch --export=ALL --dependency=afterok:%s N4_volume_benchmark/analyze_L38_more8664_ubelix.sh %s %s %s %q' \
        "$dependency" "${job_ids[@]}" "$campaign"
    printf '%s\n' "$command" > "$campaign/analyze_command.txt"
    analysis_job=$(sbatch --parsable --export=ALL --dependency="afterok:$dependency" \
        --output="$campaign/slurm_analysis_%j.out" \
        N4_volume_benchmark/analyze_L38_more8664_ubelix.sh "${job_ids[@]}" "$campaign") ||
        fail "Simulation jobs were submitted. Retry the analysis command in $campaign/analyze_command.txt."
    analysis_job=${analysis_job%%;*}
    [[ $analysis_job =~ ^[0-9]+$ ]] || fail "Unexpected analysis sbatch output: $analysis_job"
    printf '%s\n' "$analysis_job" > "$campaign/analysis_job_id.txt"
    echo "Analysis job $analysis_job will start after all three new jobs finish successfully."
    echo "All analysis outputs: $campaign"
    exit
fi

printf '\nAfter the three jobs finish, run from %s:\n\n' "$repo"
printf 'cd %q\n' "$repo"
printf 'stoc2x_jobs=('; printf ' %q' "${jobs[@]}"; printf ' )\n'
cat <<'COMMANDS'
(
    set -e
    for dir in "${stoc2x_jobs[@]}"; do
        if [[ ! -f "$dir/completed" ]]; then
            echo "Completed job output unavailable: $dir" >&2
            exit 1
        fi
    done
    module load Python SciPy-bundle matplotlib
    mkdir -p N4_L38_res
    python N4_volume_benchmark/scan_depth.py "${stoc2x_jobs[@]}" \
        --updates 30000 --targets 1.0 --bootstrap 200 \
        > N4_L38_res/L38_depth_2xstoc12.csv
)
COMMANDS
