#!/bin/bash
#SBATCH --job-name=N4_L66_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=08:00:00
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 4 || $# == 5 ]] || fail "Usage: sbatch $0 NS_JOB1 NS_JOB2 NS_JOB3 OUTPUT_DIRECTORY [MCMC_JOB_ID]"
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
output=$(realpath -m -- "$4")
[[ $output == "$repo/N4_L66_res/"* ]] || fail 'Output must be inside repository N4_L66_res.'
mkdir -p "$output"
output=$(cd "$output" && pwd -P)
[[ $output == "$repo/N4_L66_res/"* ]] || fail 'Output must resolve inside repository N4_L66_res.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
roots=()
declare -A seen=()
for id in "${@:1:3}"; do
    [[ $id =~ ^[0-9]+$ && ! -v seen[$id] ]] || fail 'Use three distinct NS job IDs.'
    seen[$id]=1
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L66/job_$id"
    [[ -f "$root/completed" && $(<"$root/lattice") == 66 && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L66 streams in $root"
    roots+=("$root")
done
mcmc_id=${5:-}
if [[ -n $mcmc_id ]]; then
    [[ $mcmc_id =~ ^[0-9]+$ ]] || fail 'MCMC_JOB_ID must be numeric.'
    mcmc="$scratch/mcmc_66_N4_beta0p9_3x100k/job_$mcmc_id"
    [[ -f "$mcmc/completed" ]] || fail "Incomplete MCMC job: $mcmc"
fi
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
"$python_exec" -c 'import numpy, scipy, matplotlib'
# scan_depth follows parent_run links, so these may also be continuation leaves.
srun --export=ALL "$python_exec" N4_volume_benchmark/scan_depth.py "${roots[@]}" \
    --updates 20000 40000 60000 80000 100000 --targets 0.7 0.75 0.8 0.85 0.9 0.95 1.0 \
    --bootstrap 200 > "$output/depth.csv.tmp"
mv "$output/depth.csv.tmp" "$output/depth.csv"
if [[ -n $mcmc_id ]]; then
    srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --output "$output/mcmc_full"
    srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --burn-in 20000 --output "$output/mcmc_burn20000"
    srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
        --mcmc "$mcmc" --ns "${roots[@]}" --updates 110000 --beta 0.9 --bins 32 \
        --burn-in 20000 --bootstrap 200 --output "$output/action_bins32_beta0p9"
fi
touch "$output/completed"
echo "Saved L66 analysis in $output"
