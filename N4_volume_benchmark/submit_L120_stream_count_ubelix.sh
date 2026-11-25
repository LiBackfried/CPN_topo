#!/bin/bash
# Login-node submission helper: analysis only, using the completed 24 streams.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 0 || ( $# == 2 && $1 == --resume ) ]] || fail "Usage: bash $0 [--resume CAMPAIGN_DIRECTORY]"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission helper on UBELIX.'
worker="$repo/N4_volume_benchmark/run_L120_stream_count_ubelix.sh"
[[ -r $worker && -r N4_volume_benchmark/scan_stream_count.py ]] || fail 'Sync both launchers and the Python driver first.'
for name in ${!SBATCH_@}; do unset "$name"; done
if (( $# )); then
    campaign=$(cd "$2" && pwd -P)
    [[ $campaign == "$repo/N4_L120_res/"stream_count24.* && -f "$campaign/cache/completed" ]] || fail 'Resume requires a completed cache inside N4_L120_res/stream_count24.*.'
    orderings=$(awk -F '\t' '$1=="orderings" {print $2}' "$campaign/settings.tsv")
    [[ $orderings =~ ^[1-9][0-9]*$ ]] && (( orderings <= 64 )) || fail 'Invalid stored ordering count.'
    prep_dependency=()
else
    scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
    [[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
    bootstrap=${STREAM_COUNT_BOOTSTRAP:-200}
    orderings=${STREAM_COUNT_ORDERINGS:-8}
    joint=${STREAM_COUNT_JOINT_DRAWS:-1000}
    seed=${STREAM_COUNT_SEED:-20261125}
    for value in "$bootstrap" "$orderings" "$joint" "$seed"; do
        [[ $value =~ ^[0-9]+$ ]] || fail 'Counts and seed must be nonnegative integers.'
    done
    (( bootstrap >= 2 && orderings >= 1 && orderings <= 64 && joint >= 2 )) || fail 'Use >=2 draws and 1-64 orderings.'
    ids=(22885157 22904262 22904264 23350703 23350705 23350707)
    roots=()
    for id in "${ids[@]}"; do
        root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
        [[ -f "$root/completed" && $(<"$root/lattice") == 120 && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L120 streams: $root"
        roots+=("$root")
    done
    mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
    [[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 120 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected completed MCMC reference: $mcmc"
    mkdir -p "$repo/N4_L120_res"
    results=$(cd "$repo/N4_L120_res" && pwd -P)
    [[ $results == "$repo/N4_L120_res" ]] || fail 'Result folder must resolve inside repository N4_L120_res.'
    campaign=$(mktemp -d "$results/stream_count24.XXXXXX")
    printf 'key\tvalue\nbootstrap\t%s\norderings\t%s\njoint_draws\t%s\nseed\t%s\n' \
        "$bootstrap" "$orderings" "$joint" "$seed" > "$campaign/settings.tsv"
    printf 'kind\tjob_id\tdirectory\n' > "$campaign/raw_inputs.tsv"
    for i in 0 1 2 3 4 5; do printf 'ns\t%s\t%s\n' "${ids[$i]}" "${roots[$i]}" >> "$campaign/raw_inputs.tsv"; done
    printf 'mcmc\t22780263\t%s\n' "$mcmc" >> "$campaign/raw_inputs.tsv"
    printf 'role\tjob_id\tdependency\n' > "$campaign/jobs.tsv"
    git rev-parse HEAD > "$campaign/git_revision.txt"
    git status --short > "$campaign/git_status.txt"
    cp "$worker" "$campaign/worker.sh"
    prep_dependency=()
fi
[[ -r "$campaign/worker.sh" ]] || fail 'Missing saved worker.'
echo "L120 stream-count campaign: $campaign"
submit() {
    local result id
    result=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 \
        --chdir="$repo" "$@") || fail "Submission failed; inspect $campaign/jobs.tsv before retrying."
    id=${result%%;*}
    [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $result (inspect squeue before retrying)."
    printf '%s\n' "$id"
}
if [[ ! -f "$campaign/cache/completed" ]]; then
    prepare=$(submit --time=12:00:00 --job-name=N4L120_count_cache \
        --output="$campaign/slurm_prepare_%j.out" "$campaign/worker.sh" prepare "$campaign")
    printf 'prepare\t%s\t-\n' "$prepare" >> "$campaign/jobs.tsv"
    prep_dependency=("--dependency=afterok:$prepare")
    echo "Submitted cache preparation $prepare"
fi
array=$(submit "${prep_dependency[@]}" --array="0-${orderings}%2" --job-name=N4L120_count_scan \
    --output="$campaign/slurm_scan_%A_%a.out" "$campaign/worker.sh" evaluate "$campaign")
printf 'evaluate_array\t%s\t%s\n' "$array" "${prep_dependency[*]:--}" >> "$campaign/jobs.tsv"
echo "Submitted evaluation array $array: baseline plus $orderings orderings, maximum two concurrent tasks"
report=$(submit --dependency="afterok:$array" --mem-per-cpu=4G --time=01:00:00 --job-name=N4L120_count_report \
    --output="$campaign/slurm_report_%j.out" "$campaign/worker.sh" collect "$campaign")
printf 'report\t%s\tafterok:%s\n' "$report" "$array" >> "$campaign/jobs.tsv"
printf 'bash %q --resume %q\n' "$repo/N4_volume_benchmark/submit_L120_stream_count_ubelix.sh" "$campaign" > "$campaign/resume_command.txt"
printf 'Queued report %s after array %s\nResults: %s/report_%s\nRecords and logs: %s\n' "$report" "$array" "$campaign" "$report" "$campaign"
