#!/bin/bash
#SBATCH --job-name=N21_ns_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL
#SBATCH --output=analysis_4x5000_%j.log

# Analyze the four 5000-update jobs (10 independent streams per job).
# Optional positional argument: output directory. By default results are kept
# inside the git checkout under analysis_results/.
# Optional environment variables: N_BOOTSTRAP (default 1000), BOOTSTRAP_SEED

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    echo "Submit this script with sbatch (not bash or ./script)." >&2
    exit 1
fi
if [[ $# -gt 1 ]]; then
    echo "Usage: sbatch $0 [OUTPUT_DIRECTORY]" >&2
    exit 1
fi

project_dir="$PWD"
scratch_root="/scratch/network/users/lb25v444/out_data"
input_roots=(
    "$scratch_root/ns_constraint_72_N21_10x5000_stoc5000/job_15484566"
    "$scratch_root/ns_constraint_72_N21_10x5000_stoc5000_fresh2/job_15985454"
    "$scratch_root/ns_constraint_72_N21_10x5000_stoc5000_fresh3/job_16235818"
    "$scratch_root/ns_constraint_72_N21_10x5000_stoc5000_fresh4/job_16236075"
)
output_dir="${1:-$project_dir/analysis_results/ns_constraint_72_N21_4x10x5000/job_${SLURM_JOB_ID}}"
n_bootstrap="${N_BOOTSTRAP:-500}"
bootstrap_seed="${BOOTSTRAP_SEED:-20261012}"

[[ "$n_bootstrap" =~ ^[0-9]+$ && "$n_bootstrap" -ge 2 ]] || {
    echo "N_BOOTSTRAP must be an integer >= 2." >&2
    exit 1
}
[[ "$bootstrap_seed" =~ ^[0-9]+$ ]] || {
    echo "BOOTSTRAP_SEED must be a non-negative integer." >&2
    exit 1
}
[[ -r "$project_dir/analyze_nested_sampling.py" ]] || {
    echo "Missing $project_dir/analyze_nested_sampling.py" >&2
    exit 1
}

# Fail early if one job folder is incomplete or points at the wrong dataset.
for root in "${input_roots[@]}"; do
    for run in {0..9}; do
        run_dir="$root/run_$run"
        for file in input.conf dati.dat topo.dat acceptance_rate.dat; do
            [[ -s "$run_dir/$file" ]] || {
                echo "Missing or empty input: $run_dir/$file" >&2
                exit 1
            }
        done
    done
done

module load Python SciPy-bundle matplotlib
trap 'module purge' EXIT
python -c 'import matplotlib, numpy' || {
    echo "The loaded UBELIX Python modules do not provide numpy and matplotlib." >&2
    echo "Check available versions with: module spider SciPy-bundle matplotlib" >&2
    exit 1
}

mkdir -p "$output_dir"
echo "Analyzing 40 streams from:"
printf '  %s\n' "${input_roots[@]}"
echo "Bootstrap replicates: $n_bootstrap (seed $bootstrap_seed)"
echo "Output: $output_dir"

srun --ntasks=1 --cpus-per-task=1 python "$project_dir/analyze_nested_sampling.py" \
    "${input_roots[@]}" \
    --output "$output_dir" \
    --bootstrap "$n_bootstrap" \
    --seed "$bootstrap_seed"

echo "Analysis complete. Summary: $output_dir/summary.txt"
