#!/bin/bash
# Prepare source-prior pilots and a separate 172800-proposal control ensemble.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 1 ]] || fail "Usage: bash $0 [all|source|ns]"
mode=${1:-all}
[[ $mode == all || $mode == source || $mode == ns ]] || fail 'Choose all, source or ns.'
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission helper on UBELIX.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
steps=${INIT_PILOT_STEPS:-10000}
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] && (( steps >= 10000 )) || fail 'Use at least 10000 pilot MC cycles.'
for file in run_L120_source_init_ubelix.sh analyze_L120_sampling_validation_ubelix.sh run_ubelix.sh analyze_sampling_validation.py; do
    [[ -r N4_volume_benchmark/$file ]] || fail "Missing file: $file"
done
declare -A used=()
baseline_ids=(22885157 22904262 22904264 23350703 23350705 23350707)
for id in "${baseline_ids[@]}"; do
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    [[ -f "$root/completed" && $(<"$root/tasks") == 4 && $(<"$root/lattice") == 120 ]] || fail "Wrong baseline: $root"
    for run in 0 1 2 3; do
        cfg="$root/run_$run/input.conf"
        awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
             END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                         v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==86400 &&
                         v["num_MC_step"]==20 && v["meas_every"]==8)}' "$cfg" || fail "Unexpected baseline config: $cfg"
        seed=$(awk '$1=="rng_seed" {print $2}' "$cfg")
        [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used[$seed] ]] || fail 'Invalid/duplicate baseline seed.'
        used[$seed]=1
    done
done
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
[[ -f "$mcmc/completed" && $(<"$mcmc/tasks") == 3 && $(<"$mcmc/lattice") == 120 ]] || fail 'Expected completed MCMC 22780263.'
for run in 0 1 2; do
    seed=$(awk '$1=="rng_seed" {print $2}' "$mcmc/run_$run/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used[$seed] ]] || fail 'Invalid/duplicate reference MCMC seed.'
    used[$seed]=1
done
module load OpenSSL/1.1
ns_executable="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22885157/cpn_ns_N4"
mc_executable=${MCMC_EXECUTABLE:-$mcmc/cpn_N4}
for kind in ns mc; do
    [[ $kind != ns || $mode != source ]] || continue
    [[ $kind != mc || $mode != ns ]] || continue
    if [[ $kind == ns ]]; then executable=$ns_executable; else executable=$mc_executable; fi
    [[ $executable == /* && -x $executable ]] || fail "Missing saved executable: $executable"
    info=$("$executable" 2>&1 || true)
    grep -Fxq 'Compiled with N = 4' <<< "$info" || fail "Expected N=4 executable: $executable"
done
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Results must resolve inside N4_L120_res.'
campaign=$(mktemp -d "$results/sampling_validation.XXXXXX")
printf 'role\tjob_id\tdirectory\tdependency\n' > "$campaign/jobs.tsv"
printf 'role\trun\tseed\n' > "$campaign/planned_seeds.tsv"
for id in "${baseline_ids[@]}"; do
    for run in 0 1 2 3; do
        cfg="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id/run_$run/input.conf"
        printf 'baseline_%s\t%s\t%s\n' "$id" "$run" "$(awk '$1=="rng_seed" {print $2}' "$cfg")" >> "$campaign/planned_seeds.tsv"
    done
done
allocate_base() {
    local word candidate collision run seed
    while :; do
        word=$(od -An -N4 -tu4 /dev/urandom); candidate=$((word%2147483300+1)); collision=0
        for run in 0 1 2 3; do seed=$((candidate+run)); if [[ -v used[$seed] ]]; then collision=1; fi; done
        (( collision )) || break
    done
    allocated=$candidate
    for run in 0 1 2 3; do used[$((candidate+run))]=1; done
}
allocate_base; source_base=$allocated
allocate_base; ns_base1=$allocated
allocate_base; ns_base2=$allocated
for spec in "source $source_base" "ns1 $ns_base1" "ns2 $ns_base2"; do
    read -r role base <<< "$spec"
    for run in 0 1 2 3; do printf '%s\t%s\t%s\n' "$role" "$run" "$((base+run))" >> "$campaign/planned_seeds.tsv"; done
done
printf 'mode=%s\npilot_MC_cycles=%s\nNS_proposals=172800\nNS_init_cycles=20\nNS_live_spacing=8\n' "$mode" "$steps" > "$campaign/settings.txt"
git rev-parse HEAD > "$campaign/git_revision.txt"
sha256sum N4_volume_benchmark/{run_L120_source_init_ubelix.sh,analyze_L120_sampling_validation_ubelix.sh,run_ubelix.sh,analyze_sampling_validation.py} > "$campaign/source_sha256.txt"
if [[ $mode != ns ]]; then sha256sum "$mc_executable" > "$campaign/mcmc_executable_sha256.txt"; fi
if [[ $mode != source ]]; then sha256sum "$ns_executable" > "$campaign/ns_executable_sha256.txt"; fi
for name in ${!SBATCH_@}; do unset "$name"; done
submit() {
    local response
    response=$(sbatch --parsable --export=ALL --chdir="$repo" "$@") || fail "Submission failed; inspect $campaign/jobs.tsv before retrying."
    submitted=${response%%;*}
    [[ $submitted =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $response (inspect scheduler before retrying)."
}
echo "L120 sampling-validation records: $campaign"
if [[ $mode != ns ]]; then
    submit --ntasks=4 --cpus-per-task=1 --output="$campaign/slurm_source_%j.out" \
        N4_volume_benchmark/run_L120_source_init_ubelix.sh "$source_base" "$steps"
    source_id=$submitted
    printf 'source_pilot\t%s\t%s\t-\n' "$source_id" "$scratch/mcmc_120_N4_beta0p7_initpilot/job_$source_id" >> "$campaign/jobs.tsv"
    echo "Submitted source pilot $source_id: two cold and two hot chains, beta=0.7, $steps cycles, seed base $source_base"
    submit --ntasks=1 --cpus-per-task=1 --mem-per-cpu=2G --time=01:00:00 --dependency="afterok:$source_id" \
        --output="$campaign/slurm_source_analysis_%j.out" N4_volume_benchmark/analyze_L120_sampling_validation_ubelix.sh source "$source_id"
    printf 'source_analysis\t%s\t%s\tafterok:%s\n' "$submitted" "$results/source_init_${source_id}_analysis_$submitted" "$source_id" >> "$campaign/jobs.tsv"
    echo "Queued source analysis $submitted after $source_id"
fi
if [[ $mode != source ]]; then
    leaves=()
    for batch in 1 2; do
        if [[ $batch == 1 ]]; then base=$ns_base1; else base=$ns_base2; fi
        parent= parent_id=
        for stage in 1 2 3; do
            dependency=()
            if [[ -n $parent ]]; then
                dependency=("--dependency=afterok:$parent_id")
                response=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
                    NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --chdir="$repo" --ntasks=4 --cpus-per-task=1 \
                    --time=12:00:00 "${dependency[@]}" --job-name="ns_L120_p172800_b${batch}_s${stage}" \
                    --output="$campaign/slurm_ns${batch}_stage${stage}_%j.out" N4_volume_benchmark/run_ubelix.sh 120 100000 "$parent") || fail "Submission failed; inspect $campaign/jobs.tsv"
            else
                response=$(env NS_SCRATCH="$scratch" NS_EXECUTABLE="$ns_executable" NS_STOC=172800 \
                    NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" \
                    sbatch --parsable --export=ALL --chdir="$repo" --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
                    --job-name="ns_L120_p172800_b${batch}_s${stage}" --output="$campaign/slurm_ns${batch}_stage${stage}_%j.out" \
                    N4_volume_benchmark/run_ubelix.sh 120 100000) || fail "Submission failed; inspect $campaign/jobs.tsv"
            fi
            submitted=${response%%;*}
            [[ $submitted =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $response"
            parent="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$submitted"
            printf 'ns%s_stage%s\t%s\t%s\t%s\n' "$batch" "$stage" "$submitted" "$parent" "${dependency[*]:--}" >> "$campaign/jobs.tsv"
            parent_id=$submitted
            echo "Submitted NS batch $batch stage $stage: job $submitted, four streams, $((stage*100000)) cumulative updates, seed base $base"
        done
        leaves+=("$parent_id")
    done
    dependency=$(IFS=:; echo "${leaves[*]}")
    printf -v retry 'sbatch --ntasks=1 --cpus-per-task=1 --dependency=afterok:%s --output=%q N4_volume_benchmark/analyze_L120_sampling_validation_ubelix.sh proposals %s %s' \
        "$dependency" "$campaign/slurm_proposals_analysis_%j.out" "${leaves[@]}"
    printf '%s\n' "$retry" > "$campaign/retry_proposals_analysis.txt"
    submit --ntasks=1 --cpus-per-task=1 --dependency="afterok:$dependency" \
        --output="$campaign/slurm_proposals_analysis_%j.out" N4_volume_benchmark/analyze_L120_sampling_validation_ubelix.sh proposals "${leaves[@]}"
    printf 'proposal_analysis\t%s\t%s\tafterok:%s\n' "$submitted" "$results/proposals172800_${leaves[0]}_analysis_$submitted" "$dependency" >> "$campaign/jobs.tsv"
    echo "Queued proposal analysis $submitted after leaves ${leaves[*]}; comparing separate baseline24 and control8"
fi
echo "Records, seeds and logs: $campaign"
