#!/bin/bash
#SBATCH --job-name=N4_Qmoments
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --array=0-4%1
#SBATCH --output=N4_charge_moments_%A_%a.log
#SBATCH --no-requeue

# Submit from the repository: sbatch N4_volume_benchmark/export_charge_moments_ubelix.sh
# Array index: 0=L22, 1=L38, 2=L66, 3=L90, 4=L120. At most one element runs at a time.
# To analyze only L90/L120: sbatch --array=3-4%1 N4_volume_benchmark/export_charge_moments_ubelix.sh
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
[[ ${SLURM_ARRAY_TASK_ID:-} =~ ^[0-4]$ ]] || fail 'Expected Slurm array index 0..4.'
[[ $# == 0 ]] || fail 'No positional arguments; select volumes with sbatch --array=... .'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo checkout.}" rev-parse --show-toplevel)
cd "$repo"
[[ -f N4_volume_benchmark/export_charge_moments.py ]] || fail 'Missing export_charge_moments.py; copy the updated repository files first.'
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
output="$repo/N4_L${lattice}_res/charge_moments/job_${SLURM_ARRAY_JOB_ID}"
[[ ! -e $output ]] || fail "Output exists; refusing to overwrite $output"
echo "Exporting all Q and Q^2 moments for L$lattice to $output"
srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" \
    "$repo/N4_volume_benchmark/export_charge_moments.py" \
    --lattice "$lattice" --scratch-root "$scratch" --output "$output" \
    --bootstrap "${N_BOOTSTRAP:-200}" --seed "${BOOTSTRAP_SEED:-20261123}" \
    --burn-in "${MCMC_BURN_IN:-20000}" --block-size "${MCMC_BLOCK_SIZE:-128}"
echo "Completed charge-moment export for L$lattice: $output"
