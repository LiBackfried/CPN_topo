#!/bin/bash
#SBATCH --job-name=N4_L120_24x300k_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=32G
#SBATCH --time=24:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# == 7 ]] || fail "Usage: sbatch $0 NS_LEAF1 NS_LEAF2 NS_LEAF3 NS_LEAF4 NS_LEAF5 NS_LEAF6 MCMC_JOB"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
declare -A seen_ids=() seen_seeds=()
roots=()
ids=("${@:1:6}")
for id in "${ids[@]}"; do
    [[ $id =~ ^[0-9]+$ && ! -v seen_ids[$id] ]] || fail 'Use six distinct numeric NS leaf IDs.'
    seen_ids[$id]=1
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    [[ -f "$root/completed" && $(<"$root/lattice") == 120 && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L120 streams: $root"
    roots+=("$root")
    for run in 0 1 2 3; do
        awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
             END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                         v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==86400 &&
                         v["num_MC_step"]==20 && v["meas_every"]==8 && v["num_micro"]==4 &&
                         v["num_norm"]==1 && v["num_cool_step"]==50 && v["meas_cool_every"]==5)}' \
             "$root/run_$run/input.conf" || fail "Unexpected NS settings: $root/run_$run"
        seed=$(awk '$1=="rng_seed" {print $2}' "$root/run_$run/input.conf")
        [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v seen_seeds[$seed] ]] || fail 'All 24 NS streams must have distinct positive seeds.'
        seen_seeds[$seed]=1
        cursor="$root/run_$run" total=0
        declare -A visited=()
        while :; do
            cursor=$(cd "$cursor" && pwd -P)
            [[ ! -v visited[$cursor] ]] || fail "Cyclic NS history: $cursor"
            visited[$cursor]=1
            points=$(awk '$1=="num_ns_meas" {print $2}' "$cursor/input.conf")
            [[ $points =~ ^[1-9][0-9]{0,8}$ ]] && (( points >= 2 )) || fail "Invalid NS segment depth: $cursor"
            total=$((total+points-1))
            [[ -f "$cursor/parent_run" ]] || break
            link=$(<"$cursor/parent_run")
            [[ -n $link ]] || fail "Empty parent link: $cursor"
            if [[ $link == /* ]]; then cursor=$(realpath -e -- "$link"); else cursor=$(realpath -e -- "$cursor/$link"); fi
        done
        unset visited
        [[ $total == 300000 ]] || fail "Expected exactly 300000 cumulative updates: $root/run_$run (found $total)"
    done
done
mcmc_id=$7
[[ $mcmc_id =~ ^[0-9]+$ && ! -v seen_ids[$mcmc_id] ]] || fail 'Use a distinct numeric MCMC job ID.'
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_$mcmc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 120 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected three completed MCMC chains: $mcmc"
for run in 0 1 2; do
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==1.0 && v["theta"]==0)}' \
         "$mcmc/run_$run/input.conf" || fail 'MCMC must match L120, beta=1.0, theta=0.'
done
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Output must resolve inside repository N4_L120_res.'
output="$results/combined24x300_analysis_${SLURM_JOB_ID}"
mkdir "$output"
printf 'kind\tjob_id\tdirectory\n' > "$output/inputs.tsv"
for index in 0 1 2 3 4 5; do printf 'ns\t%s\t%s\n' "${ids[$index]}" "${roots[$index]}" >> "$output/inputs.tsv"; done
printf 'mcmc\t%s\t%s\n' "$mcmc_id" "$mcmc" >> "$output/inputs.tsv"
git rev-parse HEAD > "$output/git_revision.txt"
sha256sum N4_volume_benchmark/{scan_depth.py,compare_action_bins.py} \
    analyze_nested_sampling.py utils/{nest_sampl.py,mcmc.py,cpn_io.py,plot_mcmc.py} > "$output/source_sha256.txt"
echo "Writing 24-stream L120 analysis to $output"
# Leaves only: the scanner checks all raw segment lengths/settings and seeds,
# joins parents and drops repeated boundary rows. Preflight fixes depth at 300k.
srun --export=ALL "$python_exec" N4_volume_benchmark/scan_depth.py "${roots[@]}" \
    --updates 180000 210000 240000 270000 300000 --targets 0.9 0.95 1.0 \
    --bootstrap 200 --seed 20261124 > "$output/depth.csv.tmp"
mv "$output/depth.csv.tmp" "$output/depth.csv"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --output "$output/mcmc_full"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --burn-in 20000 --output "$output/mcmc_burn20000"
srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
    --mcmc "$mcmc" --ns "${roots[@]}" --updates 300000 --beta 1.0 --bins 32 \
    --burn-in 20000 --block-size 512 --bootstrap 200 --seed 20261124 \
    --output "$output/action_bins32_beta1p0_block512"
touch "$output/completed"
echo "Saved 24-stream depth scan, MCMC diagnostics and beta=1.0 correlator-bin comparison in $output"
