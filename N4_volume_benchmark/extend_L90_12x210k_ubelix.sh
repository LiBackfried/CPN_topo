#!/bin/bash
# Submission driver: run with bash on the UBELIX login node.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 2 ]] || fail "Usage: bash $0 [PARENT_NS_JOB_ID [MCMC_JOB_ID]]"
parent_id=${1:-22779059} mcmc_id=${2:-22635137}
[[ $parent_id =~ ^[0-9]+$ && $mcmc_id =~ ^[0-9]+$ ]] || fail 'Job IDs must be numeric.'
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
command -v od >/dev/null || fail 'Coreutils od is required to allocate fresh seeds.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
parent="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_$parent_id"
[[ -f "$parent/completed" && $(<"$parent/lattice") == 90 && $(<"$parent/tasks") == 4 ]] || fail "Expected a completed four-stream L90 parent: $parent"
parent=$(cd "$parent" && pwd -P)
executable="$parent/cpn_ns_N4"
[[ -x $executable ]] || fail "Missing parent executable: $executable"
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'The parent executable must report N=4.'
template="$repo/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0"
for file in "$template" N4_volume_benchmark/run_ubelix.sh N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh; do
    [[ -r $file ]] || fail "Missing input: $file"
done
[[ $(awk '$1=="start" {s=$2} $1=="rng_start" {r=$2} END {print s,r}' "$template") == '1 0' ]] || fail 'The fresh-run template must use start=1 and rng_start=0.'
canonical_settings() {
    awk '{sub(/#.*/, ""); if (NF && $1 !~ /^(rng_seed|start|rng_start|num_ns_meas)$/) {$1=$1; print}}' "$@" | sort
}
# Match the exact fresh-run transformation used by run_ubelix.sh. Any other
# changed template field would create a different ensemble and must stop here.
expected=$(awk '
    /^#/ {next}
    $1=="size" {print $1,90,90; next}
    $1=="num_single_site_stoc_upd" {print $1,48600; next}
    $1=="num_MC_step" {print $1,20; next}
    $1=="meas_every" {print $1,8; next}
    {print}
' "$template" | canonical_settings)
declare -A used_seeds=()
declare -a inherited_seeds=()
# Validate all four histories and every required leaf checkpoint before any
# submission. Ancestors are read-only and must remain available for analysis.
for run in 0 1 2 3; do
    leaf="$parent/run_$run"
    for file in input.conf live_energy.dat rng_state.dat; do [[ -s "$leaf/$file" ]] || fail "Missing checkpoint/input: $leaf/$file"; done
    for live in {0..49}; do [[ -s "$leaf/conf.dat_live_$live" ]] || fail "Missing live configuration: $leaf/conf.dat_live_$live"; done
    awk '
        NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
        END {exit !(v["size"]==90 && w["size"]==90 && v["beta"]==0.7 && v["theta"]==0 &&
                    v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==48600 &&
                    v["num_MC_step"]==20 && v["meas_every"]==8 && v["num_micro"]==4 &&
                    v["num_norm"]==1 && v["num_cool_step"]==50 && v["meas_cool_every"]==5 &&
                    v["num_replica"]==1 && v["save_dead"]==0)}
    ' "$leaf/input.conf" || fail "Unexpected parent settings: $leaf"
    seed=$(awk '$1=="rng_seed" {print $2}' "$leaf/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used_seeds[$seed] ]] || fail "Invalid/duplicate inherited seed: $leaf"
    inherited_seeds+=("$seed"); used_seeds[$seed]=1
    cursor=$leaf total=0
    declare -A visited=()
    while :; do
        cursor=$(cd "$cursor" && pwd -P)
        [[ ! -v visited[$cursor] ]] || fail "Cyclic continuation history: $cursor"
        visited[$cursor]=1
        [[ -f "$cursor/../completed" && -s "$cursor/input.conf" ]] || fail "Incomplete ancestor: $cursor"
        [[ $(canonical_settings "$cursor/input.conf") == "$expected" ]] || fail "Parent history and fresh template settings differ: $cursor"
        points=$(awk '$1=="num_ns_meas" {print $2}' "$cursor/input.conf")
        [[ $points =~ ^[1-9][0-9]{0,8}$ ]] && (( points >= 2 )) || fail "Invalid segment depth: $cursor"
        total=$((total+points-1))
        [[ $(awk '$1=="rng_seed" {print $2}' "$cursor/input.conf") == "$seed" ]] || fail "Seed changes within history: $cursor"
        flags=$(awk '$1=="start" {s=$2} $1=="rng_start" {r=$2} END {print s,r}' "$cursor/input.conf")
        if [[ -f "$cursor/parent_run" ]]; then
            [[ $flags == '2 1' ]] || fail "Expected resume flags: $cursor"
            link=$(<"$cursor/parent_run")
            [[ -n $link ]] || fail "Empty parent link: $cursor"
            cursor=$(realpath -e -- "$cursor/$link")
        else
            [[ $flags == '1 0' ]] || fail "Expected fresh flags: $cursor"
            break
        fi
    done
    [[ $total == 140000 ]] || fail "Parent run_$run has $total cumulative updates; expected exactly 140000."
    unset visited
done
mcmc="$scratch/mcmc_90_N4_beta0p95_3x100k/job_$mcmc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 90 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected the completed L90 MCMC reference: $mcmc"
for run in 0 1 2; do
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==90 && w["size"]==90 && v["beta"]==0.95 && v["theta"]==0)}' \
         "$mcmc/run_$run/input.conf" || fail "Unexpected MCMC settings: $mcmc/run_$run"
    seed=$(awk '$1=="rng_seed" {print $2}' "$mcmc/run_$run/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used_seeds[$seed] ]] || fail 'Invalid/duplicate MCMC or inherited seed.'
    used_seeds[$seed]=1
done
mkdir -p "$repo/N4_L90_res"
results=$(cd "$repo/N4_L90_res" && pwd -P)
[[ $results == "$repo/N4_L90_res" ]] || fail 'Campaign records must resolve inside repository N4_L90_res.'
campaign=$(mktemp -d "$results/extend210k.XXXXXX")
manifest="$campaign/jobs.tsv"
printf 'role\tjob_id\tdirectory\tsegment_updates\tcumulative_updates\tseed_base\n' > "$manifest"
printf 'role\trun\tseed\n' > "$campaign/planned_seeds.tsv"
for run in 0 1 2 3; do printf 'continuation\t%s\t%s\n' "$run" "${inherited_seeds[$run]}" >> "$campaign/planned_seeds.tsv"; done
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
printf '%s\n' "$parent" > "$campaign/parent_directory.txt"
printf '%s\n' "$mcmc_id" > "$campaign/mcmc_job_id.txt"
sha256sum "$executable" > "$campaign/parent_executable_sha256.txt"
for name in ${!SBATCH_@}; do unset "$name"; done
echo "L90 12-stream campaign records: $campaign"
continuation=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
    NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=04:00:00 \
    --job-name=ns_L90_to210k --output="$campaign/slurm_continuation_%j.out" \
    N4_volume_benchmark/run_ubelix.sh 90 70000 "$parent") || fail "Continuation submission failed; see $manifest"
continuation=${continuation%%;*}
[[ $continuation =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $continuation (inspect squeue before retrying)."
printf 'continuation\t%s\t%s\t70000\t210000\tinherited\n' "$continuation" "$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_$continuation" >> "$manifest"
echo "Submitted continuation $continuation: four inherited streams, +70000 updates to 210000"
jobs=("$continuation")
for batch in 1 2; do
    base=${fresh_bases[$((batch-1))]}
    id=$(env NS_SCRATCH="$scratch" NS_EXECUTABLE="$executable" NS_STOC=48600 \
        NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" \
        sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=08:00:00 \
        --job-name="ns_L90_new${batch}_210k" --output="$campaign/slurm_fresh${batch}_%j.out" \
        N4_volume_benchmark/run_ubelix.sh 90 210000) || fail "Submission failed; successful jobs are listed in $manifest. Inspect them before retrying."
    id=${id%%;*}
    [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $id (inspect squeue before retrying)."
    jobs+=("$id")
    printf 'fresh%s\t%s\t%s\t210000\t210000\t%s\n' "$batch" "$id" "$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_$id" "$base" >> "$manifest"
    echo "Submitted fresh batch $id: four new streams, 210000 updates, seed base $base"
done
dependency=$(IFS=:; echo "${jobs[*]}")
printf -v retry 'sbatch --export=ALL --ntasks=1 --cpus-per-task=1 --dependency=afterok:%s --output=%q N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh %s %s %s %s' \
    "$dependency" "$campaign/slurm_analysis_%j.out" "${jobs[@]}" "$mcmc_id"
printf '%s\n' "$retry" > "$campaign/analyze_command.txt"
analysis=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 --dependency="afterok:$dependency" \
    --output="$campaign/slurm_analysis_%j.out" N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh "${jobs[@]}" "$mcmc_id") ||
    fail "All three NS jobs submitted; retry analysis using $campaign/analyze_command.txt"
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $analysis (inspect squeue before retrying)."
printf 'analysis\t%s\t%s\t-\t210000\t-\n' "$analysis" "$results/combined210_ns${continuation}_analysis_${analysis}" >> "$manifest"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
echo "Queued analysis $analysis after all three NS jobs; reusing MCMC $mcmc_id"
echo "Records, planned seeds, Slurm logs and analysis retry command: $campaign"
