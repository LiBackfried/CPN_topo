#!/bin/bash
#SBATCH --job-name=ns_L38_action_bins
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=01:00:00

set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

[[ $# == 3 ]] || fail "Usage: sbatch $0 DOUBLED_JOB1 DOUBLED_JOB2 DOUBLED_JOB3"
cd "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo repository root.}"
[[ -f N4_volume_benchmark/compare_action_bins.py ]] || fail 'Submit from the CPN_topo repository root.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
base="$scratch/ns_N4_beta0p7_volume_benchmark/L38"
mcmc="$scratch/mcmc_38_N4_beta1p0_3x100k/job_22121710"
baseline=("$base/job_22133588" "$base/job_22133589" "$base/job_22133590" "$base/job_22120845")
doubled=()
declare -A seen=()
for job in "$@"; do
    [[ $job =~ ^[0-9]+$ && ! -v seen[$job] ]] || fail 'Supply three distinct doubled-proposal job IDs.'
    seen[$job]=1
    dir="$base/job_$job"
    [[ -f "$dir/completed" && -r "$dir/run_0/input.conf" ]] || fail "Incomplete job: $dir"
    proposals=$(awk '$1 == "num_single_site_stoc_upd" {print $2}' "$dir/run_0/input.conf")
    [[ $proposals == 8664 ]] || fail "Expected 8,664 stochastic proposals in $dir"
    doubled+=("$dir")
done

for dir in "$mcmc" "${baseline[@]}"; do
    [[ -f "$dir/completed" ]] || fail "Incomplete job: $dir"
done

module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
"$python_exec" -c 'import numpy, scipy, matplotlib'
output=N4_L38_res/action_bins
srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
    --mcmc "$mcmc" --ns "${baseline[@]}" --output "$output/stoc4332"
srun --export=ALL "$python_exec" N4_volume_benchmark/compare_action_bins.py \
    --mcmc "$mcmc" --ns "${doubled[@]}" --output "$output/stoc8664"
