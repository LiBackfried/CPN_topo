#!/bin/bash
# Add sixteen independently seeded 172800-proposal streams to the existing eight.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# == 0 ]] || fail "Usage: bash $0 (from the updated UBELIX checkout)"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission helper on UBELIX.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
for file in run_ubelix.sh analyze_L120_proposals24_ubelix.sh analyze_sampling_validation.py plot_L120_proposal_charges.py; do
    [[ -r N4_volume_benchmark/$file ]] || fail "Missing file: $file"
done
declare -A used=()
existing_rows=() excluded_rows=()
baseline=(22885157 22904262 22904264 23350703 23350705 23350707)
old_control=(23502237 23502240)
reserve_seed() {
    local seed=$1 role=$2
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v used[$seed] ]] || fail "Invalid/duplicate seed $seed ($role)."
    used[$seed]=1; excluded_rows+=("$role"$'\t'"$seed")
}
# Check lightweight ancestry/config records without loading histories on the login node.
check_ns() {
    local id=$1 stoc=$2 role=$3 root run leaf path cfg parent seed points total start rng
    local -A visited=()
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    [[ -f "$root/completed" && $(<"$root/tasks") == 4 && $(<"$root/lattice") == 120 ]] || fail "Wrong completed NS root: $root"
    for run in 0 1 2 3; do
        leaf="$root/run_$run"; path=$leaf; total=0; visited=()
        seed=$(awk '$1=="rng_seed" {print $2}' "$leaf/input.conf")
        reserve_seed "$seed" "$role/$id/run_$run"
        existing_rows+=("$role"$'\t'"$id"$'\t'"$run"$'\t'"$seed"$'\t'"$leaf")
        while :; do
            path=$(cd "$path" && pwd -P)
            [[ ! -v visited[$path] ]] || fail "Cyclic history at $path"
            visited[$path]=1; cfg="$path/input.conf"
            for file in input.conf dati.dat topo.dat acceptance_rate.dat log.dat; do
                [[ -s "$path/$file" ]] || fail "Missing history file: $path/$file"
            done
            grep -Fxq 'Theory: 2d CP^{N-1} model with N = 4' "$path/log.dat" || fail "Expected N=4 log: $path"
            if [[ -f "$path/parent_run" ]]; then start=2; rng=1; else start=1; rng=0; fi
            points=$(awk -v stoc="$stoc" -v seed="$seed" -v start="$start" -v rng="$rng" '
                NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
                END {if (!(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                    v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==stoc && v["num_MC_step"]==20 &&
                    v["meas_every"]==8 && v["rng_seed"]==seed && v["start"]==start && v["rng_start"]==rng &&
                    v["num_micro"]==4 && v["num_norm"]==1 && v["num_replica"]==1 &&
                    v["num_cool_step"]==50 && v["meas_cool_every"]==5 && v["num_ns_meas"] ~ /^[1-9][0-9]*$/ && v["num_ns_meas"]>1)) exit 1;
                    print v["num_ns_meas"]-1}' "$cfg") || fail "Unexpected historical config: $cfg"
            total=$((total+points))
            [[ -f "$path/parent_run" ]] || break
            parent=$(<"$path/parent_run"); [[ -n $parent ]] || fail "Empty parent link: $path"
            path="$path/$parent"
        done
        (( total == 300000 )) || fail "Expected cumulative 300k updates: $leaf (found $total)"
    done
}
for id in "${baseline[@]}"; do check_ns "$id" 86400 baseline24; done
for id in "${old_control[@]}"; do check_ns "$id" 172800 old_control8; done
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
[[ -f "$mcmc/completed" && $(<"$mcmc/tasks") == 3 && $(<"$mcmc/lattice") == 120 ]] || fail 'Expected completed MCMC 22780263.'
for run in 0 1 2; do
    cfg="$mcmc/run_$run/input.conf"
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3} END {exit !(v["size"]==120 && w["size"]==120 &&
        v["beta"]==1 && v["theta"]==0 && v["meas_every"]==10 && v["num_MC_step"]==1000000 &&
        v["num_cool_step"]==50 && v["meas_cool_every"]==5)}' "$cfg" || fail "Unexpected reference MCMC: $cfg"
    for file in dati.dat topo.dat log.dat; do [[ -s "$mcmc/run_$run/$file" ]] || fail "Missing MCMC file: $file"; done
    reserve_seed "$(awk '$1=="rng_seed" {print $2}' "$cfg")" "mcmc/run_$run"
done
# Also avoid the independently seeded source-prior pilots.
for seed in 2126073774 2126073775 2126073776 2126073777; do reserve_seed "$seed" source_pilot; done
# Avoid planned seeds from earlier invocations, including partial submissions.
for planned in "$repo"/N4_L120_res/proposals172800_add16.*/planned_seeds.tsv; do
    [[ -f $planned ]] || continue
    while IFS=$'\t' read -r batch run seed; do
        [[ $batch != batch ]] || continue
        [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) || fail "Invalid prior seed record: $planned"
        if [[ ! -v used[$seed] ]]; then reserve_seed "$seed" "earlier_plan/$batch/run_$run"; fi
    done < "$planned"
done
module load OpenSSL/1.1
executable="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/cpn_ns_N4"
[[ -x $executable ]] || fail "Missing saved executable: $executable"
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'Expected the saved N=4 executable.'
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Results must resolve inside N4_L120_res.'
campaign=$(mktemp -d "$results/proposals172800_add16.XXXXXX")
printf 'role\tjob_id\tdirectory\tdependency\tseed_base\tcumulative_updates\n' > "$campaign/jobs.tsv"
printf 'cohort\tjob_id\trun\tseed\tdirectory\n%s\n' "$(printf '%s\n' "${existing_rows[@]}")" > "$campaign/existing_streams.tsv"
printf 'role\tseed\n%s\n' "$(printf '%s\n' "${excluded_rows[@]}")" > "$campaign/excluded_seeds.tsv"
printf 'batch\trun\tseed\n' > "$campaign/planned_seeds.tsv"
bases=()
for batch in 1 2 3 4; do
    while :; do
        word=$(od -An -N4 -tu4 /dev/urandom); candidate=$((word%2147483300+1)); collision=0
        for run in 0 1 2 3; do if [[ -v used[$((candidate+run))] ]]; then collision=1; fi; done
        (( collision )) || break
    done
    bases+=("$candidate")
    for run in 0 1 2 3; do
        used[$((candidate+run))]=1
        printf '%s\t%s\t%s\n' "$batch" "$run" "$((candidate+run))" >> "$campaign/planned_seeds.tsv"
    done
done
printf 'N=4\nL=120\nsource_beta=0.7\nproposals=172800\nlive_points=50\ninit_cycles=20\nlive_spacing=8\nold_streams=8\nfresh_streams=16\nupdates_per_stream=300000\nstages=3x100000\n' > "$campaign/settings.txt"
git rev-parse HEAD > "$campaign/git_revision.txt"
sha256sum "$executable" > "$campaign/executable_sha256.txt"
sha256sum N4_volume_benchmark/{add_L120_proposals_8to24_ubelix.sh,analyze_L120_proposals24_ubelix.sh,run_ubelix.sh,analyze_sampling_validation.py,plot_L120_proposal_charges.py} > "$campaign/source_sha256.txt"
for name in ${!SBATCH_@}; do unset "$name"; done
echo "L120 doubled-proposal 24-stream campaign records: $campaign"
leaves=()
for batch in 1 2 3 4; do
    base=${bases[$((batch-1))]}; parent=; parent_id=
    for stage in 1 2 3; do
        dependency=()
        if [[ -n $parent ]]; then
            dependency=("--dependency=afterok:$parent_id")
            response=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
                NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --chdir="$repo" --ntasks=4 --cpus-per-task=1 \
                --time=12:00:00 "${dependency[@]}" --job-name="ns_L120_p172800_add16_b${batch}_s${stage}" \
                --output="$campaign/slurm_b${batch}_s${stage}_%j.out" N4_volume_benchmark/run_ubelix.sh 120 100000 "$parent") || fail "Submission failed; inspect $campaign/jobs.tsv before retrying."
        else
            response=$(env NS_SCRATCH="$scratch" NS_EXECUTABLE="$executable" NS_STOC=172800 NS_INIT_SWEEPS=20 \
                NS_INIT_SPACING=8 NS_SEED_BASE="$base" sbatch --parsable --export=ALL --chdir="$repo" \
                --ntasks=4 --cpus-per-task=1 --time=12:00:00 --job-name="ns_L120_p172800_add16_b${batch}_s${stage}" \
                --output="$campaign/slurm_b${batch}_s${stage}_%j.out" N4_volume_benchmark/run_ubelix.sh 120 100000) || fail "Submission failed; inspect $campaign/jobs.tsv before retrying."
        fi
        id=${response%%;*}; [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $response; inspect scheduler before retrying."
        parent="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
        printf 'fresh%s_stage%s\t%s\t%s\t%s\t%s\t%s\n' "$batch" "$stage" "$id" "$parent" "${dependency[*]:--}" "$base" "$((stage*100000))" >> "$campaign/jobs.tsv"
        parent_id=$id
        echo "Submitted fresh batch $batch stage $stage: $id, four streams, $((stage*100000)) cumulative updates, seed base $base"
    done
    leaves+=("$parent_id")
done
dependency=$(IFS=:; echo "${leaves[*]}")
printf -v command 'env NS_SCRATCH=%q sbatch --chdir=%q --dependency=afterok:%s --output=%q N4_volume_benchmark/analyze_L120_proposals24_ubelix.sh %s %s %s %s' \
    "$scratch" "$repo" "$dependency" "$campaign/slurm_analysis_%j.out" "${leaves[@]}"
printf '%s\n' "$command" > "$campaign/retry_analysis.txt"
response=$(NS_SCRATCH="$scratch" sbatch --parsable --export=ALL --chdir="$repo" --dependency="afterok:$dependency" \
    --output="$campaign/slurm_analysis_%j.out" N4_volume_benchmark/analyze_L120_proposals24_ubelix.sh "${leaves[@]}") || fail "Analysis submission failed; use $campaign/retry_analysis.txt"
id=${response%%;*}; [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected analysis sbatch response: $response"
printf 'analysis\t%s\t%s\tafterok:%s\t-\t300000\n' "$id" "$results/proposals172800_24streams_analysis_$id" "$dependency" >> "$campaign/jobs.tsv"
echo "Queued analysis $id after ${leaves[*]}; reusing old leaves 23502237 23502240 and MCMC 22780263"
echo "Records, seeds and logs: $campaign"
