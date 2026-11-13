#!/bin/bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

(( $# == 0 )) || fail "Usage: bash $0"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this script on UBELIX.'

scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
base="$scratch/ns_N4_beta0p7_volume_benchmark/L38"
original="$base/job_22120845"
[[ -f "$original/completed" && -x "$original/cpn_ns_N4" ]] ||
    fail "Expected the completed original job and its executable in $original"

export NS_SCRATCH="$scratch"
export NS_EXECUTABLE="$original/cpn_ns_N4"
unset NS_SEED_BASE NS_STOC NS_INIT_SWEEPS NS_INIT_SPACING

fresh_jobs=()
for batch in 1 2 3; do
    job=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=00:30:00 \
        --job-name="ns_L38_fresh_$batch" N4_volume_benchmark/run_ubelix.sh 38 35000) ||
        fail "Submission $batch failed. Jobs printed above were already submitted."
    job=${job%%;*}
    [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $job"
    fresh_jobs+=("$base/job_$job")
    echo "Submitted job $job (4 chains): $base/job_$job"
done

printf '\nAfter the three jobs finish, run from %s:\n\n' "$repo"
printf 'module load Python SciPy-bundle matplotlib\n'
printf 'fresh_jobs=('; printf ' %q' "${fresh_jobs[@]}"; printf ' )\n'
printf 'original=%q\n' "$original"
cat <<'COMMANDS'
# First analyze the 12 fresh chains, then pool with the original four.
(
    for dir in "${fresh_jobs[@]}" "$original"; do
        if [[ ! -f "$dir/completed" ]]; then
            echo "Completed job output unavailable: $dir" >&2
            exit 1
        fi
    done
    python N4_volume_benchmark/scan_depth.py "${fresh_jobs[@]}" \
        --updates 30000 --targets 0.8 0.9 1.0 --bootstrap 200 > L38_depth_fresh12.csv &&
    python N4_volume_benchmark/scan_depth.py "${fresh_jobs[@]}" "$original" \
        --updates 30000 --targets 0.8 0.9 1.0 --bootstrap 200 > L38_depth_combined16.csv
)
COMMANDS
