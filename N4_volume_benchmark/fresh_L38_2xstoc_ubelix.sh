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
export NS_STOC=8664
unset NS_SEED_BASE NS_INIT_SWEEPS NS_INIT_SPACING

jobs=()
for batch in 1 2 3; do
    job=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=00:45:00 \
        --job-name="ns_L38_2xstoc_$batch" N4_volume_benchmark/run_ubelix.sh 38 35000) ||
        fail "Submission $batch failed. Jobs printed above were already submitted."
    job=${job%%;*}
    [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $job"
    jobs+=("$base/job_$job")
    echo "Submitted job $job (4 chains, NS_STOC=$NS_STOC): $base/job_$job"
done

printf '\nAfter the three jobs finish, run from %s:\n\n' "$repo"
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
