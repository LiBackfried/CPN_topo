#!/bin/bash
set -euo pipefail

if (( $# > 1 )); then
    echo "Usage: bash $0 [parent_job_dir]" >&2
    exit 1
fi

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
parent=${1:-$scratch/ns_N4_beta0p7_volume_benchmark/L38/job_22097065}
parent=${parent%/}
if [[ $scratch != /* ]]; then
    echo 'NS_SCRATCH must be an absolute path.' >&2
    exit 1
fi
if [[ ${parent##*/} != job_22097065 || ! -f "$parent/completed" ]]; then
    echo "Expected the completed parent job 22097065 at $parent" >&2
    exit 1
fi
parent=$(cd "$parent" && pwd -P)

cd "$repo"
export NS_SCRATCH="$scratch"
exec sbatch --ntasks=4 --cpus-per-task=1 --time=00:10:00 \
    --job-name=ns_L38_continue_22097065 \
    N4_volume_benchmark/run_ubelix.sh 38 5000 "$parent"
