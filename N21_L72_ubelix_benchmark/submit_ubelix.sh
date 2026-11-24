#!/bin/bash
# Login-node submission driver. Workers themselves are submitted with sbatch.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 1 ]] || fail "Usage: bash $0 [NS_UPDATES_PER_STREAM, default 5000]"
steps=${1:-5000}
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] || fail 'Use a positive update count, at most seven digits.'
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
setup="$repo/N21_L72_ubelix_benchmark"
executable=${NS_EXECUTABLE:-$repo/cpn_ns_N21}
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
seed_base=${NS_SEED_BASE:-21720001}
[[ $seed_base =~ ^[1-9][0-9]{0,9}$ ]] && (( seed_base + 109 < 2147483399 )) || fail 'Invalid ran2 seed range.'
[[ $scratch == /* && $executable == /* && -x $executable ]] || fail 'Use absolute scratch/binary paths and build cpn_ns_N21 first.'
command -v sbatch >/dev/null || fail 'Run this driver on UBELIX.'
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info" || fail 'Executable must report N = 21.'
grep -aFq '#NS loop wall time:' "$executable" || fail 'Use build_N21_ubelix.sh to include loop wall timing.'
mkdir -p "$scratch"
campaign=$(mktemp -d "$scratch/ns_N21_L72_benchmark.XXXXXXXX")
snapshot="$campaign/snapshot"
mkdir "$snapshot" "$snapshot/utils"
cp "$setup/"{run_ubelix.sh,analyze_ubelix.sh,summarize.py,input.template} "$snapshot/"
cp "$repo/analyze_nested_sampling.py" "$snapshot/"
cp "$repo/utils/"*.py "$snapshot/utils/"
cp "$executable" "$snapshot/cpn_ns_N21"
if [[ -f ${executable}.build_info.txt ]]; then cp "${executable}.build_info.txt" "$snapshot/build_info.txt"; fi
sha256sum "$snapshot/cpn_ns_N21" > "$snapshot/executable.sha256"
(cd "$snapshot"; sha256sum ./*.sh ./*.py input.template utils/*.py > scripts.sha256)
manifest="$campaign/jobs.tsv"
printf 'proposals\tupdates\tseed_base\tjob_id\tjob_directory\n' > "$manifest"
# Inherited sbatch environment overrides must not shrink the allocation.
for name in ${!SBATCH_@}; do unset "$name"; done
echo "Campaign: $campaign"
jobs=()
for proposals in 15500 31000; do
    arm_seeds=$seed_base
    [[ $proposals == 15500 ]] || arm_seeds=$((seed_base+100))
    job=$(sbatch --parsable --export=ALL --chdir="$campaign" --ntasks=10 --cpus-per-task=1 \
        --mem-per-cpu=2G --time=02:00:00 --job-name="N21_L72_p${proposals}" \
        --output="$campaign/slurm_%j.out" --error="$campaign/slurm_%j.err" \
        "$snapshot/run_ubelix.sh" "$proposals" "$steps" "$arm_seeds" "$campaign") ||
        fail "Submission failed; inspect $manifest for jobs already submitted."
    job=${job%%;*}
    [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $job; inspect squeue before retrying."
    jobs+=("$job")
    printf '%s\t%s\t%s\t%s\t%s\n' "$proposals" "$steps" "$arm_seeds" "$job" "$campaign/job_$job" >> "$manifest"
    echo "Submitted $job: 10 streams, $steps NS updates, $proposals proposals/update."
done
analysis=$(sbatch --parsable --export=ALL --chdir="$campaign" --ntasks=1 --cpus-per-task=1 \
    --mem-per-cpu=8G --time=02:00:00 --dependency="afterok:${jobs[0]}:${jobs[1]}" \
    --output="$campaign/analysis_%j.out" --error="$campaign/analysis_%j.err" \
    "$snapshot/analyze_ubelix.sh" "$campaign") || fail "Analysis submission failed; simulation jobs are in $manifest."
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected analysis job response: $analysis"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
printf 'sacct -j %s,%s,%s --format=JobID,JobName,State,ReqCPUS,AllocCPUS,Elapsed,MaxRSS\n' \
    "${jobs[0]}" "${jobs[1]}" "$analysis" | tee "$campaign/check_command.txt"
echo "Dependent analysis job: $analysis; results: $campaign/analysis_$analysis"
echo 'No direct MCMC reference is submitted by this NS benchmark.'
