#!/bin/bash
#SBATCH --job-name=N4L120_Qproposals
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=04:00:00
#SBATCH --output=N4_L120_charge_comparison_%j.log
#SBATCH --no-requeue
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 0 && ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit this file with sbatch from CPN_topo.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
comparison="$repo/N4_L120_res/proposals172800_23502237_analysis_23502241"
[[ -f "$comparison/completed" && -s "$comparison/inputs.json" ]] || fail 'Expected completed proposal analysis 23502241.'
scratch=${VOLUME_DATA_ROOT:-${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}}
[[ $scratch == /* && -d $scratch ]] || fail 'Expected an absolute scratch out_data root.'
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
"$python_exec" -c 'import numpy, scipy, matplotlib'
output="$repo/N4_L120_res/proposal_charge_distributions/job_$SLURM_JOB_ID"
[[ ! -e $output ]] || fail "Refusing to overwrite $output"
srun --export=ALL --ntasks=1 --cpus-per-task=1 "$python_exec" -u \
    N4_volume_benchmark/plot_L120_proposal_charges.py analyze \
    --comparison "$comparison/inputs.json" --scratch-root "$scratch" --output "$output" \
    --bootstrap "${N_BOOTSTRAP:-200}" --seed "${BOOTSTRAP_SEED:-20261126}"
git rev-parse HEAD > "$output/git_revision.txt"
echo "Charge distributions and comparison figures: $output"
