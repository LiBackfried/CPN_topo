#!/bin/bash
#SBATCH -J N21_ns_resume2
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=09:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

set -euo pipefail
if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    echo "Submit this script with sbatch (not bash or ./script)." >&2
    exit 1
fi
# The original fresh2 job ID identifies the existing scratch output folder.
resume_job_id="${1:-15985454}"
if [[ $# -gt 1 || ! "$resume_job_id" =~ ^[0-9]+$ ]]; then
    echo "Usage: sbatch run_ns_constraint_72_N21_10x5000_stoc5000_fresh2_ubelix.sh ORIGINAL_JOB_ID" >&2
    exit 1
fi
module load OpenSSL/1.1
trap 'module purge' EXIT

export project_dir="$PWD"
export run_group="ns_constraint_72_N21_10x5000_stoc5000_fresh2"
export output_root="/scratch/network/users/lb25v444/out_data/${run_group}/job_${resume_job_id}"

[[ -x "$project_dir/cpn_ns" ]] || { echo "Build cpn_ns for N=21 first." >&2; exit 1; }
for run in {0..9}; do
    [[ -r "$project_dir/config_files/$run_group/run_$run" ]] || exit 1
done
# Validate every checkpoint before starting any chain.
for run in {0..9}; do
    outdir="$output_root/run_$run"
    for file in rng_state.dat live_energy.dat conf.dat_live_{0..49}; do
        [[ -s "$outdir/$file" ]] || { echo "Missing checkpoint: $outdir/$file" >&2; exit 1; }
    done
done
echo "Continuing 10 chains in $output_root for 4500 more updates each"

srun --ntasks=10 --cpus-per-task=1 --export=ALL /bin/bash -c '
set -euo pipefail
outdir="$output_root/run_${SLURM_PROCID}"
[[ -d "$outdir" ]]
cp "$project_dir/config_files/$run_group/run_${SLURM_PROCID}" "$outdir/input_resume_${SLURM_JOB_ID}.conf"
# Relative config paths and acceptance_rate.dat must all resolve on scratch.
cd "$outdir"
if [[ -f log.dat ]]; then cp log.dat "log_before_resume_${SLURM_JOB_ID}.dat"; fi
exec "$project_dir/cpn_ns" "input_resume_${SLURM_JOB_ID}.conf" >> stdout.log 2>> stderr.log
'
