#!/bin/bash
# Login-node submission driver. Workers themselves are submitted with sbatch.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
setup="$repo/N21_L72_ubelix_benchmark"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
reference=
if [[ ${1:-} == near-source && $# -le 2 ]]; then
    steps=20000
    seed_base=${NS_SEED_BASE:-21722001}
    reference=$(cd "${2:-$scratch/ns_N21_L72_benchmark.5NegZsTv}" && pwd -P) ||
        fail 'The original 5,000-update campaign is required.'
    [[ -r $reference/jobs.tsv && -r $reference/snapshot/executable.sha256 ]] ||
        fail 'The original campaign manifest or executable hash is missing.'
    sha256sum -c "$reference/snapshot/executable.sha256"
    executable="$reference/snapshot/cpn_ns_N21"
    analysis_worker=scan_targets_ubelix.sh
else
    [[ $# -le 1 ]] || fail "Usage: bash $0 [NS_UPDATES_PER_STREAM] or bash $0 near-source [ORIGINAL_CAMPAIGN]"
    steps=${1:-5000}
    seed_base=${NS_SEED_BASE:-21720001}
    executable=${NS_EXECUTABLE:-$repo/cpn_ns_N21}
    analysis_worker=analyze_ubelix.sh
fi
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] || fail 'Use a positive update count, at most seven digits.'
[[ $seed_base =~ ^[1-9][0-9]{0,9}$ ]] && (( seed_base + 109 < 2147483399 )) || fail 'Invalid ran2 seed range.'
if [[ -n $reference ]]; then
    awk -F '\t' -v seed="$seed_base" '
        NR>1 {
            old=$3
            if ($2!=5000 || old !~ /^[1-9][0-9]*$/) bad=1
            if ((seed<=old+9 && old<=seed+9) ||
                (seed+100<=old+9 && old<=seed+109)) bad=1
            seen[$1]++
        }
        END {exit (bad || NR!=3 || seen[15500]!=1 || seen[31000]!=1)}
    ' "$reference/jobs.tsv" || fail 'Expected two original 5,000-update arms with seed ranges disjoint from the new jobs.'
fi
[[ $scratch == /* && $executable == /* && -x $executable ]] || fail 'Use absolute scratch/binary paths and build cpn_ns_N21 first.'
command -v sbatch >/dev/null || fail 'Run this driver on UBELIX.'
module purge
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
if [[ -n $reference ]]; then
    cp "$setup/scan_targets_ubelix.sh" "$snapshot/"
    mkdir "$snapshot/N4_volume_benchmark"
    cp "$repo/N4_volume_benchmark/scan_depth.py" "$snapshot/N4_volume_benchmark/"
    if [[ -r $reference/snapshot/build_info.txt ]]; then
        cp "$reference/snapshot/build_info.txt" "$snapshot/build_info.txt"
    fi
fi
sha256sum "$snapshot/cpn_ns_N21" > "$snapshot/executable.sha256"
(
    cd "$snapshot"
    files=(./*.sh ./*.py input.template utils/*.py)
    if [[ -n $reference ]]; then files+=(N4_volume_benchmark/scan_depth.py); fi
    sha256sum "${files[@]}" > scripts.sha256
)
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
analysis_args=("$campaign")
if [[ -n $reference ]]; then analysis_args+=("$reference"); fi
analysis=$(cd "$repo" && sbatch --parsable --export=ALL --chdir="$campaign" --ntasks=1 --cpus-per-task=1 \
    --mem-per-cpu=8G --time=02:00:00 --dependency="afterok:${jobs[0]}:${jobs[1]}" \
    --output="$campaign/analysis_%j.out" --error="$campaign/analysis_%j.err" \
    "$snapshot/$analysis_worker" "${analysis_args[@]}") || fail "Analysis submission failed; simulation jobs are in $manifest."
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected analysis job response: $analysis"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
printf 'sacct -j %s,%s,%s --format=JobID,JobName,State,ReqCPUS,AllocCPUS,Elapsed,MaxRSS\n' \
    "${jobs[0]}" "${jobs[1]}" "$analysis" | tee "$campaign/check_command.txt"
analysis_output="$campaign/analysis_$analysis"
if [[ -n $reference ]]; then analysis_output="$repo/N21_benchmark_results/near_source_$analysis"; fi
printf '%s\n' "$analysis_output" > "$campaign/analysis_output.txt"
echo "Dependent analysis job: $analysis; results: $analysis_output"
echo 'No direct MCMC reference is submitted by this NS benchmark.'
