#!/bin/bash
#SBATCH -J N21_ns_10x5000
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=06:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

set -euo pipefail
module load OpenSSL/1.1
trap 'module purge' EXIT

export project_dir="$PWD"
export run_group="ns_constraint_72_N21_10x5000_stoc5000"
export output_root="/scratch/network/users/lb25v444/out_data/${run_group}/job_${SLURM_JOB_ID}"

[[ -x "$project_dir/cpn_ns" ]] || { echo "Build cpn_ns for N=21 first." >&2; exit 1; }
for run in {0..9}; do
    [[ -r "$project_dir/config_files/$run_group/run_$run" ]] || exit 1
done
mkdir -p "$(dirname "$output_root")"
# Refuse to reuse a directory, including on a Slurm requeue of this fresh-start job.
mkdir "$output_root"
echo "Writing 10 chains to $output_root"

srun --ntasks=10 --cpus-per-task=1 --export=ALL /bin/bash -c '
set -euo pipefail
outdir="$output_root/run_${SLURM_PROCID}"
mkdir "$outdir"
cp "$project_dir/config_files/$run_group/run_${SLURM_PROCID}" "$outdir/input.conf"
# Relative config paths and acceptance_rate.dat must all resolve on scratch.
cd "$outdir"
exec "$project_dir/cpn_ns" input.conf > stdout.log 2> stderr.log
'
