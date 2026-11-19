#!/bin/bash
#SBATCH --job-name=N4_L90_12x210k_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=12:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
fail() { echo "$*" >&2; exit 1; }
[[ $# == 4 ]] || fail "Usage: sbatch $0 CONTINUATION_JOB FRESH_JOB1 FRESH_JOB2 MCMC_JOB"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
declare -A seen_ids=() seen_seeds=()
roots=()
for id in "${@:1:3}"; do
    [[ $id =~ ^[0-9]+$ && ! -v seen_ids[$id] ]] || fail 'Use three distinct numeric NS job IDs, with one continuation leaf and two fresh jobs.'
    seen_ids[$id]=1
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_$id"
    [[ -f "$root/completed" && $(<"$root/lattice") == 90 && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L90 streams: $root"
    roots+=("$root")
    for run in 0 1 2 3; do
        awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
             END {exit !(v["size"]==90 && w["size"]==90 && v["beta"]==0.7 && v["theta"]==0 &&
                         v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==48600 &&
                         v["num_MC_step"]==20 && v["meas_every"]==8)}' \
             "$root/run_$run/input.conf" || fail "Unexpected NS settings: $root/run_$run"
        seed=$(awk '$1=="rng_seed" {print $2}' "$root/run_$run/input.conf")
        [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v seen_seeds[$seed] ]] || fail 'All twelve NS streams must have distinct positive seeds.'
        seen_seeds[$seed]=1
    done
done
mcmc_id=$4
[[ $mcmc_id =~ ^[0-9]+$ ]] || fail 'MCMC job ID must be numeric.'
mcmc="$scratch/mcmc_90_N4_beta0p95_3x100k/job_$mcmc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 90 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected the completed MCMC reference: $mcmc"
for run in 0 1 2; do
    awk 'NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
         END {exit !(v["size"]==90 && w["size"]==90 && v["beta"]==0.95 && v["theta"]==0)}' \
         "$mcmc/run_$run/input.conf" || fail 'MCMC settings must match L90, beta=0.95, theta=0.'
done
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
mkdir -p "$repo/N4_L90_res"
results=$(cd "$repo/N4_L90_res" && pwd -P)
[[ $results == "$repo/N4_L90_res" ]] || fail 'Output must resolve inside repository N4_L90_res.'
output="$results/combined210_ns${1}_analysis_${SLURM_JOB_ID}"
mkdir "$output"
printf 'kind\tjob_id\tdirectory\n' > "$output/inputs.tsv"
# Keep positional IDs separate from the roots when writing the input record.
ids=("${@:1:3}")
for index in 0 1 2; do printf 'ns\t%s\t%s\n' "${ids[$index]}" "${roots[$index]}" >> "$output/inputs.tsv"; done
printf 'mcmc\t%s\t%s\n' "$mcmc_id" "$mcmc" >> "$output/inputs.tsv"
echo "Writing twelve-stream L90 analysis to $output"
# Pass leaves only. The scanner joins ancestors, drops repeated boundary rows,
# checks common settings/seeds and merges equal cumulative prefixes by energy.
srun --export=ALL "$python_exec" N4_volume_benchmark/scan_depth.py "${roots[@]}" \
    --updates 100000 120000 140000 160000 180000 200000 210000 \
    --targets 0.9 0.95 1.0 --bootstrap 200 --seed 20261119 > "$output/depth.csv.tmp"
mv "$output/depth.csv.tmp" "$output/depth.csv"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --output "$output/mcmc_full"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --burn-in 20000 --output "$output/mcmc_burn20000"
srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
    --mcmc "$mcmc" --ns "${roots[@]}" --updates 210000 --beta 0.95 --bins 32 \
    --burn-in 20000 --block-size 128 --bootstrap 200 --seed 20261119 --output "$output/action_bins32_beta0p95"
touch "$output/completed"
echo "Saved combined depth scan, MCMC diagnostics and beta=0.95 correlator-bin comparison in $output"
