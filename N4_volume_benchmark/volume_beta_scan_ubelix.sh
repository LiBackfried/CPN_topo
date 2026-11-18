#!/bin/bash
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL

# Worker submitted by submit_volume_beta_scan_ubelix.sh, with resources/logs
# selected there. Run data are read from scratch; all results stay in the repo.
set -euo pipefail
[[ -n "${SLURM_JOB_ID:-}" ]] || { echo "Submit this worker with sbatch." >&2; exit 1; }
[[ $# -eq 3 ]] || { echo "Usage: sbatch $0 {22|38|66|compare} PROJECT_DIR OUTPUT_DIR" >&2; exit 1; }
# sbatch --mem supplies SLURM_MEM_PER_NODE for this allocation. Drop stale
# per-CPU/GPU values exported from a parent allocation before invoking srun.
unset SLURM_MEM_PER_CPU SLURM_MEM_PER_GPU
mode="$1"
project_dir="$(realpath "$2")"
output_dir="$(realpath "$3")"
case "$output_dir/" in
    "$project_dir/N4_L38_res/"*) ;;
    "$project_dir/N4_L66_res/"*) ;;
    *) echo "Output must be under repository N4_L38_res/ or N4_L66_res/." >&2; exit 1 ;;
esac
cd "$project_dir"
scratch_root="${VOLUME_DATA_ROOT:-/scratch/network/users/lb25v444/out_data}"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 MPLBACKEND=Agg
module load Python SciPy-bundle matplotlib
python_bin="$(type -P python3 || type -P python)"
"$python_bin" -c 'import matplotlib, numpy, scipy'

if [[ "$mode" == compare ]]; then
    mcmc_args=()
    if [[ -n "${MCMC_L22_DIR:-}" ]]; then
        mcmc_args+=(--mcmc-l22 "$MCMC_L22_DIR")
    else
        mcmc_args+=(--mcmc-l22-search "$scratch_root/mcmc_22_N4_beta0p7_3x1M")
    fi
    # An explicitly supplied directory is required to be complete. The known
    # L38 reference is included when present; its absence is recorded otherwise.
    if [[ -n "${MCMC_L38_DIR:-}" ]]; then
        mcmc_args+=(--mcmc-l38 "$MCMC_L38_DIR")
    elif [[ -d "$scratch_root/mcmc_38_N4_beta1p0_3x100k/job_22121710" ]]; then
        mcmc_args+=(--mcmc-l38 "$scratch_root/mcmc_38_N4_beta1p0_3x100k/job_22121710")
    fi
    if [[ "${INCLUDE_L66:-0}" == 1 ]]; then
        mcmc_args+=(--l66 "$output_dir/L66/beta_scan.csv")
        if [[ -n "${MCMC_L66_DIR:-}" ]]; then
            mcmc_args+=(--mcmc-l66 "$MCMC_L66_DIR")
        elif [[ -d "$scratch_root/mcmc_66_N4_beta0p9_3x100k/job_22587511" ]]; then
            mcmc_args+=(--mcmc-l66 "$scratch_root/mcmc_66_N4_beta0p9_3x100k/job_22587511")
        fi
    fi
    srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" \
        "$project_dir/N4_volume_benchmark/plot_volume_betas.py" \
        --l22 "$output_dir/L22/beta_scan.csv" --l38 "$output_dir/L38/beta_scan.csv" \
        --output "$output_dir" --burn-in "${MCMC_BURN_IN:-20000}" \
        --block-size "${MCMC_BLOCK_SIZE:-128}" "${mcmc_args[@]}"
    exit
fi

roots=()
selection_args=()
case "$mode" in
    22)
        group="$scratch_root/ns_constraint_22_N4_beta0p7_10x50000_stoc1500"
        jobs=(19135775 19678209 19692937 19692936 20008149 20008651 20010266 20008148
              20388977 20388978 20389384 20388976 20525014 20525015 20525016 20525009
              20684460 20684461 20684462 20686257 20687600 20687618 20687905 20688780
              20689657 20690092 20690588 20691674 20691875 20692744 20692746 20684452)
        first=(0 10 50 75 100 125 150 175 200 225 250 275 300 325 350 375 400 425 450 475 500 525 550 575 600 625 650 675 700 725 750 775)
        last=(9 49 74 99 124 149 174 199 224 249 274 299 324 349 374 399 424 449 474 499 524 549 574 599 624 649 674 699 724 749 774 799)
        available_chains=800
        expected_chains="${L22_MAX_STREAMS:-100}"
        selection_args=(--max-streams "$expected_chains" --stream-selection-seed "${STREAM_SELECTION_SEED:-20261118}")
        stoc=1500
        ;;
    38)
        group="$scratch_root/ns_N4_beta0p7_volume_benchmark/L38"
        jobs=(22320950 22320951 22320952 22583507 22583508 22583509)
        first=(0 0 0 0 0 0)
        last=(3 3 3 3 3 3)
        expected_chains=24
        available_chains=24
        stoc=8664
        ;;
    66)
        group="$scratch_root/ns_N4_beta0p7_volume_benchmark/L66"
        jobs=(22587433 22587434 22587435)
        first=(0 0 0)
        last=(3 3 3)
        expected_chains=12
        available_chains=12
        stoc=26136
        ;;
    *) echo "Unknown mode: $mode" >&2; exit 1 ;;
esac
for index in "${!jobs[@]}"; do
    for ((run=first[index]; run<=last[index]; run++)); do
        path="$group/job_${jobs[$index]}/run_$run"
        for file in input.conf dati.dat topo.dat acceptance_rate.dat log.dat; do
            [[ -s "$path/$file" ]] || { echo "Missing or empty: $path/$file" >&2; exit 1; }
        done
        roots+=("$path")
    done
done
[[ "${#roots[@]}" -eq "$available_chains" ]]
mkdir -p "$output_dir/L$mode"
srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" \
    "$project_dir/N4_volume_benchmark/scan_volume_betas.py" "${roots[@]}" \
    --output "$output_dir/L$mode" --bootstrap "${N_BOOTSTRAP:-200}" \
    --seed "${BOOTSTRAP_SEED:-20261118}" --expected-lattice "$mode" \
    --expected-stoc "$stoc" --expected-chains "$expected_chains" \
    --expected-available-chains "$available_chains" "${selection_args[@]}"
