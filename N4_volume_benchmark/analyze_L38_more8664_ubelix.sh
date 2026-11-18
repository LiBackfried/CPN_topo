#!/bin/bash
#SBATCH --job-name=ns_L38_more8664_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00

set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 4 ]] || fail "Usage: sbatch $0 NEW_JOB1 NEW_JOB2 NEW_JOB3 OUTPUT_DIRECTORY"
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo repository root.}" rev-parse --show-toplevel)
cd "$repo"
[[ -f N4_volume_benchmark/compare_action_bins.py ]] || fail 'Submit from the CPN_topo repository root.'
requested_output=$(realpath -m -- "$4")
[[ $requested_output == "$repo/N4_L38_res/"* ]] || fail 'Output must be a directory inside the repository N4_L38_res directory.'
mkdir -p "$requested_output"
output=$(cd "$requested_output" && pwd -P)
[[ $output == "$repo/N4_L38_res/"* ]] || fail 'Output must be a directory inside the repository N4_L38_res directory.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
base="$scratch/ns_N4_beta0p7_volume_benchmark/L38"
mcmc="$scratch/mcmc_38_N4_beta1p0_3x100k/job_22121710"
baseline=("$base/job_22133588" "$base/job_22133589" "$base/job_22133590" "$base/job_22120845")
previous=("$base/job_22320950" "$base/job_22320951" "$base/job_22320952")
fresh=()
declare -A seen=([22320950]=1 [22320951]=1 [22320952]=1 [22133588]=1 [22133589]=1 [22133590]=1 [22120845]=1)
for id in "${@:1:3}"; do
    [[ $id =~ ^[0-9]+$ && ! -v seen[$id] ]] || fail 'Use three distinct fresh job IDs.'
    seen[$id]=1
    fresh+=("$base/job_$id")
done
combined=("${previous[@]}" "${fresh[@]}")
for dir in "$mcmc" "${baseline[@]}" "${combined[@]}"; do
    [[ -f "$dir/completed" ]] || fail "Incomplete job: $dir"
done
for dir in "${combined[@]}"; do
    [[ $(<"$dir/tasks") == 4 && $(<"$dir/lattice") == 38 ]] || fail "Expected four L=38 chains in $dir"
    for run in 0 1 2 3; do
        awk '$1=="num_single_site_stoc_upd" {stoc=$2}
             $1=="num_ns_meas" {meas=$2} $1=="start" {start=$2} $1=="rng_start" {rng=$2}
             END {exit !(stoc==8664 && meas==35001 && start==1 && rng==0)}' "$dir/run_$run/input.conf" ||
            fail "Expected a fresh 35,000-update 8,664-proposal chain in $dir/run_$run"
    done
done
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
"$python_exec" -c 'import numpy, scipy, matplotlib'
echo "Writing all analysis outputs to $output"
for group in fresh12 previous12 combined24 baseline16; do
    case $group in
        fresh12) roots=("${fresh[@]}") ;;
        previous12) roots=("${previous[@]}") ;;
        combined24) roots=("${combined[@]}") ;;
        baseline16) roots=("${baseline[@]}") ;;
    esac
    # Publish a CSV after the Python analysis succeeds.
    srun --export=ALL "$python_exec" N4_volume_benchmark/scan_depth.py "${roots[@]}" \
        --updates 30000 --targets 0.8 0.9 1.0 --bootstrap 200 > "$output/depth_${group}.csv.tmp"
    mv "$output/depth_${group}.csv.tmp" "$output/depth_${group}.csv"
    srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
        --mcmc "$mcmc" --ns "${roots[@]}" --bins 32 --output "$output/action_bins32/$group"
done
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --burn-in 20000 \
    --output "$output/mcmc_burn20000"
touch "$output/completed"
echo "Completed all analyses in $output"
