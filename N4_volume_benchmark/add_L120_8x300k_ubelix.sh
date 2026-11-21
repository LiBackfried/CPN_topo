#!/bin/bash
# Submission driver: run with bash on a UBELIX login node.
# Eight new independent streams; each is checkpointed at 150k then reaches 300k.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 2 ]] || fail "Usage: bash $0 [EXISTING_NS_JOB_ID [MCMC_JOB_ID]]"
existing_id=${1:-22885157} mcmc_id=${2:-22780263}
[[ $existing_id =~ ^[0-9]+$ && $mcmc_id =~ ^[0-9]+$ ]] || fail 'Job IDs must be numeric.'
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
command -v od >/dev/null || fail 'Coreutils od is required to allocate fresh seeds.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
existing="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$existing_id"
[[ -f "$existing/completed" && $(<"$existing/lattice") == 120 && $(<"$existing/tasks") == 4 ]] || fail "Expected a completed four-stream L120 ensemble: $existing"
existing=$(cd "$existing" && pwd -P)
executable="$existing/cpn_ns_N4"
[[ -x $executable ]] || fail "Missing saved executable: $executable"
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'The saved NS executable must report N=4.'
template="$repo/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0"
for file in "$template" N4_volume_benchmark/run_ubelix.sh N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh; do
    [[ -r $file ]] || fail "Missing input: $file"
done
[[ $(awk '$1=="start" {s=$2} $1=="rng_start" {r=$2} END {print s,r}' "$template") == '1 0' ]] || fail 'The template must use fresh start/RNG flags.'
canonical_settings() {
    awk '{sub(/#.*/, ""); if (NF && $1 !~ /^(rng_seed|start|rng_start|num_ns_meas)$/) {$1=$1; print}}' "$@" | sort
}
expected=$(awk '
    /^#/ {next}
    $1=="size" {print $1,120,120; next}
    $1=="num_single_site_stoc_upd" {print $1,86400; next}
    $1=="num_MC_step" {print $1,20; next}
    $1=="meas_every" {print $1,8; next}
    {print}
' "$template" | canonical_settings)
declare -A used_seeds=()
existing_seeds=()
# Existing streams are read only and will not be continued. Validate their
# histories/raw analysis inputs, not their live checkpoints, before submitting.
for run in 0 1 2 3; do
    leaf="$existing/run_$run"
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                     v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==86400 &&
                     v["num_MC_step"]==20 && v["meas_every"]==8 && v["num_micro"]==4 &&
                     v["num_norm"]==1 && v["num_cool_step"]==50 && v["meas_cool_every"]==5 &&
                     v["num_replica"]==1 && v["save_dead"]==0)}' "$leaf/input.conf" || fail "Unexpected existing settings: $leaf"
    seed=$(awk '$1=="rng_seed" {print $2}' "$leaf/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used_seeds[$seed] ]] || fail 'Invalid/duplicate existing NS seed.'
    existing_seeds+=("$seed"); used_seeds[$seed]=1
    cursor=$leaf total=0
    declare -A visited=()
    while :; do
        cursor=$(cd "$cursor" && pwd -P)
        [[ ! -v visited[$cursor] ]] || fail "Cyclic history: $cursor"
        visited[$cursor]=1
        [[ -f "$cursor/../completed" ]] || fail "Incomplete ancestor: $cursor"
        for file in input.conf dati.dat topo.dat log.dat acceptance_rate.dat; do
            [[ -s "$cursor/$file" ]] || fail "Missing analysis input: $cursor/$file"
        done
        grep -Fxq 'Theory: 2d CP^{N-1} model with N = 4' "$cursor/log.dat" || fail "Expected an N=4 NS log: $cursor"
        [[ $(canonical_settings "$cursor/input.conf") == "$expected" ]] || fail "Existing history and fresh template settings differ: $cursor"
        points=$(awk '$1=="num_ns_meas" {print $2}' "$cursor/input.conf")
        [[ $points =~ ^[1-9][0-9]{0,8}$ ]] && (( points >= 2 )) || fail "Invalid segment depth: $cursor"
        total=$((total+points-1))
        [[ $(awk '$1=="rng_seed" {print $2}' "$cursor/input.conf") == "$seed" ]] || fail "Seed changes within history: $cursor"
        flags=$(awk '$1=="start" {s=$2} $1=="rng_start" {r=$2} END {print s,r}' "$cursor/input.conf")
        if [[ -f "$cursor/parent_run" ]]; then
            [[ $flags == '2 1' ]] || fail "Expected resume flags: $cursor"
            link=$(<"$cursor/parent_run")
            [[ -n $link ]] || fail "Empty parent link: $cursor"
            if [[ $link == /* ]]; then cursor=$(realpath -e -- "$link"); else cursor=$(realpath -e -- "$cursor/$link"); fi
        else
            [[ $flags == '1 0' ]] || fail "Expected fresh flags: $cursor"
            break
        fi
    done
    [[ $total == 300000 ]] || fail "Existing run_$run has $total cumulative updates; expected exactly 300000."
    unset visited
done
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_$mcmc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 120 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected the completed L120 MCMC reference: $mcmc"
for run in 0 1 2; do
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==1.0 && v["theta"]==0)}' \
         "$mcmc/run_$run/input.conf" || fail 'MCMC must match L120, beta=1.0, theta=0.'
    for file in dati.dat topo.dat log.dat; do [[ -s "$mcmc/run_$run/$file" ]] || fail "Missing MCMC input: $mcmc/run_$run/$file"; done
    grep -Fxq 'Theory: 2d CP^{N-1} model with N = 4' "$mcmc/run_$run/log.dat" || fail 'The MCMC reference must report N=4.'
    seed=$(awk '$1=="rng_seed" {print $2}' "$mcmc/run_$run/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used_seeds[$seed] ]] || fail 'Invalid/duplicate MCMC or existing NS seed.'
    used_seeds[$seed]=1
done
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Campaign records must resolve inside repository N4_L120_res.'
campaign=$(mktemp -d "$results/add8_300k.XXXXXX")
manifest="$campaign/jobs.tsv"
printf 'role\tjob_id\tdirectory\tsegment_updates\tcumulative_updates\tseed_base\tdependency\n' > "$manifest"
printf 'kind\tjob_id\tdirectory\nns_existing\t%s\t%s\nmcmc\t%s\t%s\n' "$existing_id" "$existing" "$mcmc_id" "$mcmc" > "$campaign/existing_inputs.tsv"
printf 'role\trun\tseed\n' > "$campaign/planned_seeds.tsv"
for run in 0 1 2 3; do printf 'existing\t%s\t%s\n' "$run" "${existing_seeds[$run]}" >> "$campaign/planned_seeds.tsv"; done
fresh_bases=()
for batch in 1 2; do
    while :; do
        word=$(od -An -N4 -tu4 /dev/urandom)
        base=$((word%2147483300+1))
        collision=0
        for run in 0 1 2 3; do seed=$((base+run)); if [[ -v used_seeds[$seed] ]]; then collision=1; fi; done
        (( collision )) || break
    done
    fresh_bases+=("$base")
    for run in 0 1 2 3; do seed=$((base+run)); used_seeds[$seed]=1; printf 'fresh%s\t%s\t%s\n' "$batch" "$run" "$seed" >> "$campaign/planned_seeds.tsv"; done
done
sha256sum "$executable" > "$campaign/existing_executable_sha256.txt"
for name in ${!SBATCH_@}; do unset "$name"; done
echo "L120 eight-stream campaign records: $campaign"
leaves=()
for batch in 1 2; do
    base=${fresh_bases[$((batch-1))]}
    start_job=$(env NS_SCRATCH="$scratch" NS_EXECUTABLE="$executable" NS_STOC=86400 \
        NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" \
        sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
        --job-name="ns_L120_new${batch}_start" --output="$campaign/slurm_fresh${batch}_start_%j.out" \
        N4_volume_benchmark/run_ubelix.sh 120 150000) || fail "Submission failed; inspect $manifest before retrying."
    start_job=${start_job%%;*}
    [[ $start_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $start_job (inspect squeue before retrying)."
    start_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$start_job"
    printf 'fresh%s_start\t%s\t%s\t150000\t150000\t%s\t-\n' "$batch" "$start_job" "$start_root" "$base" >> "$manifest"
    echo "Submitted fresh batch $start_job: four new L120 streams, first 150000 updates, seed base $base"
    leaf_job=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
        NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
        --dependency="afterok:$start_job" --job-name="ns_L120_new${batch}_to300k" \
        --output="$campaign/slurm_fresh${batch}_leaf_%j.out" \
        N4_volume_benchmark/run_ubelix.sh 120 150000 "$start_root") || fail "Start job $start_job submitted; continuation submission failed. Inspect $manifest before retrying."
    leaf_job=${leaf_job%%;*}
    [[ $leaf_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $leaf_job (inspect squeue before retrying)."
    leaf_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$leaf_job"
    printf 'fresh%s_leaf\t%s\t%s\t150000\t300000\t%s\tafterok:%s\n' "$batch" "$leaf_job" "$leaf_root" "$base" "$start_job" >> "$manifest"
    leaves+=("$leaf_job")
    echo "Queued leaf $leaf_job after $start_job: same four streams, +150000 to 300000"
done
dependency=$(IFS=:; echo "${leaves[*]}")
printf -v retry 'sbatch --export=ALL --ntasks=1 --cpus-per-task=1 --dependency=afterok:%s --output=%q N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh %s %s %s %s' \
    "$dependency" "$campaign/slurm_analysis_%j.out" "$existing_id" "${leaves[@]}" "$mcmc_id"
printf '%s\n' "$retry" > "$campaign/analyze_command.txt"
analysis=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 --dependency="afterok:$dependency" \
    --output="$campaign/slurm_analysis_%j.out" N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh \
    "$existing_id" "${leaves[@]}" "$mcmc_id") || fail "Four simulation jobs submitted; retry analysis using $campaign/analyze_command.txt"
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $analysis (inspect squeue before retrying)."
printf 'analysis\t%s\t%s\t-\t300000\t-\tafterok:%s\n' "$analysis" "$results/combined300_ns${existing_id}_analysis_${analysis}" "$dependency" >> "$manifest"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
echo "Queued analysis $analysis after leaves ${leaves[*]}; combining twelve streams and reusing MCMC $mcmc_id"
echo "Records, planned seeds, Slurm logs and analysis retry command: $campaign"
