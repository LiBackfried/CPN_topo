#!/bin/bash
# Run with bash on UBELIX: add twelve independent streams to the existing twelve.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 4 ]] || fail "Usage: bash $0 [EXISTING_LEAF1 [EXISTING_LEAF2 [EXISTING_LEAF3 [MCMC_JOB]]]]"
existing_ids=("${1:-22885157}" "${2:-22904262}" "${3:-22904264}")
mcmc_id=${4:-22780263}
declare -A seen_ids=() used_seeds=()
for id in "${existing_ids[@]}" "$mcmc_id"; do
    [[ $id =~ ^[0-9]+$ && ! -v seen_ids[$id] ]] || fail 'Use distinct numeric job IDs.'
    seen_ids[$id]=1
done
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
command -v od >/dev/null || fail 'Coreutils od is required to allocate fresh seeds.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
template="$repo/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0"
analysis_script=N4_volume_benchmark/analyze_L120_24x300k_ubelix.sh
for file in "$template" N4_volume_benchmark/run_ubelix.sh "$analysis_script"; do
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
existing_roots=() existing_seeds=()
for id in "${existing_ids[@]}"; do
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    [[ -f "$root/completed" && $(<"$root/lattice") == 120 && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L120 streams: $root"
    root=$(cd "$root" && pwd -P)
    existing_roots+=("$root")
    for run in 0 1 2 3; do
        leaf="$root/run_$run"
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
            [[ $(canonical_settings "$cursor/input.conf") == "$expected" ]] || fail "History and fresh template settings differ: $cursor"
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
        [[ $total == 300000 ]] || fail "Expected 300000 cumulative updates, found $total: $leaf"
        unset visited
    done
done
executable="${existing_roots[0]}/cpn_ns_N4"
[[ -x $executable ]] || fail "Missing saved executable: $executable"
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'The saved NS executable must report N=4.'
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_$mcmc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 120 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected three completed L120 MCMC chains: $mcmc"
for run in 0 1 2; do
    leaf="$mcmc/run_$run"
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==1.0 && v["theta"]==0)}' "$leaf/input.conf" || fail "Wrong MCMC settings: $leaf"
    for file in dati.dat topo.dat log.dat; do [[ -s "$leaf/$file" ]] || fail "Missing MCMC input: $leaf/$file"; done
    grep -Fxq 'Theory: 2d CP^{N-1} model with N = 4' "$leaf/log.dat" || fail "Expected N=4 MCMC log: $leaf"
    seed=$(awk '$1=="rng_seed" {print $2}' "$leaf/input.conf")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used_seeds[$seed] ]] || fail 'Invalid/duplicate MCMC or existing NS seed.'
    used_seeds[$seed]=1
done
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Campaign records must resolve inside repository N4_L120_res.'
campaign=$(mktemp -d "$results/add12_to24_300k.XXXXXX")
manifest="$campaign/jobs.tsv"
printf 'role\tjob_id\tdirectory\tsegment_updates\tcumulative_updates\tseed_base\tdependency\n' > "$manifest"
printf 'kind\tjob_id\tdirectory\n' > "$campaign/existing_inputs.tsv"
printf 'role\trun\tseed\n' > "$campaign/planned_seeds.tsv"
for group in 0 1 2; do
    printf 'ns_existing%s\t%s\t%s\n' "$((group+1))" "${existing_ids[$group]}" "${existing_roots[$group]}" >> "$campaign/existing_inputs.tsv"
    for run in 0 1 2 3; do
        printf 'existing%s\t%s\t%s\n' "$((group+1))" "$run" "${existing_seeds[$((4*group+run))]}" >> "$campaign/planned_seeds.tsv"
    done
done
printf 'mcmc\t%s\t%s\n' "$mcmc_id" "$mcmc" >> "$campaign/existing_inputs.tsv"
fresh_bases=()
for batch in 1 2 3; do
    while :; do
        word=$(od -An -N4 -tu4 /dev/urandom)
        base=$((word%2147483300+1))
        collision=0
        for run in 0 1 2 3; do seed=$((base+run)); if [[ -v used_seeds[$seed] ]]; then collision=1; fi; done
        (( collision )) || break
    done
    fresh_bases+=("$base")
    for run in 0 1 2 3; do
        seed=$((base+run)); used_seeds[$seed]=1
        printf 'fresh%s\t%s\t%s\n' "$batch" "$run" "$seed" >> "$campaign/planned_seeds.tsv"
    done
done
sha256sum "$executable" > "$campaign/existing_executable_sha256.txt"
sha256sum "$template" N4_volume_benchmark/run_ubelix.sh "$analysis_script" "${BASH_SOURCE[0]}" > "$campaign/source_sha256.txt"
for name in ${!SBATCH_@}; do unset "$name"; done
echo "L120 24-stream campaign records: $campaign"
leaves=()
for batch in 1 2 3; do
    base=${fresh_bases[$((batch-1))]}
    start_job=$(env NS_SCRATCH="$scratch" NS_EXECUTABLE="$executable" NS_STOC=86400 \
        NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" \
        sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
        --job-name="ns_L120_add12_${batch}_start" --output="$campaign/slurm_fresh${batch}_start_%j.out" \
        N4_volume_benchmark/run_ubelix.sh 120 150000) || fail "Submission failed; inspect $manifest before retrying."
    start_job=${start_job%%;*}
    [[ $start_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $start_job (inspect squeue before retrying)."
    start_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$start_job"
    printf 'fresh%s_start\t%s\t%s\t150000\t150000\t%s\t-\n' "$batch" "$start_job" "$start_root" "$base" >> "$manifest"
    echo "Submitted fresh batch $start_job: four new L120 streams, first 150000 updates, seed base $base"
    leaf_job=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
        NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
        --dependency="afterok:$start_job" --job-name="ns_L120_add12_${batch}_to300k" \
        --output="$campaign/slurm_fresh${batch}_leaf_%j.out" \
        N4_volume_benchmark/run_ubelix.sh 120 150000 "$start_root") || fail "Start job $start_job submitted; leaf submission failed. Inspect $manifest before retrying."
    leaf_job=${leaf_job%%;*}
    [[ $leaf_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $leaf_job (inspect squeue before retrying)."
    leaf_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$leaf_job"
    printf 'fresh%s_leaf\t%s\t%s\t150000\t300000\t%s\tafterok:%s\n' "$batch" "$leaf_job" "$leaf_root" "$base" "$start_job" >> "$manifest"
    leaves+=("$leaf_job")
    echo "Queued leaf $leaf_job after $start_job: same four streams, +150000 to 300000"
done
dependency=$(IFS=:; echo "${leaves[*]}")
printf -v retry 'sbatch --export=ALL --ntasks=1 --cpus-per-task=1 --dependency=afterok:%s --output=%q %q %s %s %s %s %s %s %s' \
    "$dependency" "$campaign/slurm_analysis_%j.out" "$analysis_script" "${existing_ids[@]}" "${leaves[@]}" "$mcmc_id"
printf '%s\n' "$retry" > "$campaign/analyze_command.txt"
analysis=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 --dependency="afterok:$dependency" \
    --output="$campaign/slurm_analysis_%j.out" "$analysis_script" "${existing_ids[@]}" "${leaves[@]}" "$mcmc_id") || fail "Six simulation jobs submitted; retry analysis using $campaign/analyze_command.txt"
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $analysis (inspect squeue before retrying)."
printf 'analysis\t%s\t%s\t-\t300000\t-\tafterok:%s\n' "$analysis" "$results/combined24x300_analysis_${analysis}" "$dependency" >> "$manifest"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
echo "Queued analysis $analysis after leaves ${leaves[*]}; combining 24 streams and reusing MCMC $mcmc_id"
echo "Records, planned seeds, Slurm logs and analysis retry command: $campaign"
