#!/bin/bash
#SBATCH --job-name=N4_L22_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=28G
#SBATCH --time=06:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL
#SBATCH --output=analysis_N4_L22_%j.log

# Analyze the 200 independent streams from the four N=4, L=22 production jobs.
# Optional positional argument: output directory. By default results are kept
# inside the git checkout under analysis_results/.
# Optional environment variables: N_BOOTSTRAP (default 500), BOOTSTRAP_SEED,
# and TARGET_BETA (reweights beta only; theta remains fixed).

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
scratch_root="/scratch/network/users/lb25v444/out_data/ns_constraint_22_N4_beta0p7_10x50000_stoc1500"
input_roots=(
    "$scratch_root/job_19135775"
    "$scratch_root/job_19678209"
    "$scratch_root/job_19692937"
    "$scratch_root/job_19692936"
    "$scratch_root/job_20008149"
    "$scratch_root/job_20008651"
    "$scratch_root/job_20010266"
    "$scratch_root/job_20008148"
    "$scratch_root/job_20388977"
    "$scratch_root/job_20388978"
    "$scratch_root/job_20389384"
    "$scratch_root/job_20388976"
    "$scratch_root/job_20525014"
    "$scratch_root/job_20525015"
    "$scratch_root/job_20525016"
    "$scratch_root/job_20525009"
)
first_runs=(0 10 50 75 100 125 150 175 200 225 250 275 300 325 350 375)
last_runs=(9 49 74 99 124 149 174 199 224 249 274 299 324 349 374 399)
output_dir="${1:-$project_dir/analysis_results/ns_constraint_22_N4_beta0p7_400x50000_stoc1500/job_${SLURM_JOB_ID}}"
n_bootstrap="${N_BOOTSTRAP:-500}"
bootstrap_seed="${BOOTSTRAP_SEED:-20261023}"
beta_args=(--cpn-n 4)
if [[ -n "${TARGET_BETA:-}" ]]; then
    beta_args+=(--target-beta "$TARGET_BETA")
fi

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

# Fail before loading Python if any of the 100 stream outputs is incomplete.
for index in "${!input_roots[@]}"; do
    root="${input_roots[$index]}"
    for ((run = first_runs[index]; run <= last_runs[index]; run++)); do
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
python_bin="$(type -P python3 || type -P python || true)"
[[ -n "$python_bin" && -x "$python_bin" ]] || {
    echo "Could not find a Python executable after loading the UBELIX modules." >&2
    echo "Check available versions with: module spider Python" >&2
    exit 1
}
"$python_bin" -c 'import matplotlib, numpy, scipy' || {
    echo "The loaded UBELIX Python modules do not provide numpy, scipy, and matplotlib." >&2
    echo "Check available versions with: module spider SciPy-bundle matplotlib" >&2
    exit 1
}
echo "Python: $python_bin"

mkdir -p "$output_dir"
echo "Analyzing 400 streams from:"
printf '  %s\n' "${input_roots[@]}"
echo "Bootstrap replicates: $n_bootstrap (seed $bootstrap_seed)"
echo "Target beta: ${TARGET_BETA:-source beta 0.7}"
echo "Output: $output_dir"

srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" "$project_dir/analyze_nested_sampling.py" \
    "${input_roots[@]}" \
    --output "$output_dir" \
    --bootstrap "$n_bootstrap" \
    --seed "$bootstrap_seed" \
    "${beta_args[@]}"

echo "Analysis complete. Summary: $output_dir/summary.txt"
