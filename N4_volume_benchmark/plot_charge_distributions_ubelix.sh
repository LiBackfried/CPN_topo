#!/bin/bash
#SBATCH --job-name=N4_Qdist
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --array=0-4%1
#SBATCH --output=N4_charge_distributions_%A_%a.log
#SBATCH --no-requeue

# Submit from the checkout: sbatch N4_volume_benchmark/plot_charge_distributions_ubelix.sh
# Array 0=L22, 1=L38, 2=L66, 3=L90, 4=L120; one element runs at a time.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
[[ ${SLURM_ARRAY_TASK_ID:-} =~ ^[0-4]$ && ${SLURM_ARRAY_JOB_ID:-} =~ ^[0-9]+$ ]] || fail 'Expected a Slurm array with indices 0..4.'
[[ $# == 0 ]] || fail 'Select volumes with sbatch --array=...; no positional arguments.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo checkout.}" rev-parse --show-toplevel)
cd "$repo"
[[ -f N4_volume_benchmark/plot_charge_distributions.py ]] || fail 'Missing plot_charge_distributions.py.'
lattices=(22 38 66 90 120)
lattice=${lattices[$SLURM_ARRAY_TASK_ID]}
scratch=${VOLUME_DATA_ROOT:-${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}}
[[ $scratch == /* && -d $scratch ]] || fail "Expected an absolute scratch out_data root: $scratch"
unset SLURM_MEM_PER_CPU SLURM_MEM_PER_GPU
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
module load Python SciPy-bundle matplotlib
python_bin=$(type -P python3 || type -P python)
[[ $python_bin == /* ]] || fail 'Python must resolve to an absolute executable.'
"$python_bin" -c 'import numpy, scipy, matplotlib'
output="$repo/N4_L${lattice}_res/charge_distributions/job_${SLURM_ARRAY_JOB_ID}"
[[ ! -e $output ]] || fail "Refusing to overwrite $output"
manifest_variable="NS_MANIFEST_L${lattice}"
manifest=${!manifest_variable:-}
extra=()
[[ -z $manifest ]] || extra+=(--manifest "$manifest")
echo "Exporting and plotting Q distributions for L$lattice: $output"
srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" \
    "$repo/N4_volume_benchmark/plot_charge_distributions.py" analyze \
    --lattice "$lattice" --scratch-root "$scratch" --output "$output" \
    --bootstrap "${N_BOOTSTRAP:-200}" --seed "${BOOTSTRAP_SEED:-20261125}" \
    --burn-in "${MCMC_BURN_IN:-20000}" --block-size "${MCMC_BLOCK_SIZE:-128}" \
    --bin-width "${CHARGE_BIN_WIDTH:-1}" --probability-floor "${PROBABILITY_FLOOR:-1e-6}" \
    "${extra[@]}"
echo "Completed Q distributions for L$lattice: $output"
