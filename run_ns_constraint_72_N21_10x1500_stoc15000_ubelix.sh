#!/bin/bash
#SBATCH -J N21_ns_15k
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=09:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    echo "Submit this script with sbatch (not bash or ./script)." >&2
    exit 1
fi

module load OpenSSL/1.1
trap 'module purge' EXIT

export project_dir="$PWD"
export run_group="ns_constraint_72_N21_10x1500_stoc15000"
export output_root="/scratch/network/users/lb25v444/out_data/${run_group}/job_${SLURM_JOB_ID}"

[[ -x "$project_dir/cpn_ns" ]] || {
    echo "Missing executable: $project_dir/cpn_ns (build it for N=21 first)." >&2
    exit 1
}

for run in {0..9}; do
    [[ -r "$project_dir/config_files/$run_group/run_$run" ]] || {
        echo "Missing config: $project_dir/config_files/$run_group/run_$run" >&2
        exit 1
    }
done

mkdir -p "$output_root"
echo "Launching 10 fresh chains in $output_root"
echo "Each chain: 50 live points, 15000 stochastic updates/NS update, 1500 NS updates"

srun --ntasks=10 --cpus-per-task=1 --export=ALL /bin/bash -c '
set -euo pipefail
run_id="$SLURM_PROCID"
outdir="$output_root/run_${run_id}"
mkdir -p "$outdir"
cp "$project_dir/config_files/$run_group/run_${run_id}" "$outdir/input.conf"
cd "$outdir"
exec "$project_dir/cpn_ns" input.conf > stdout.log 2> stderr.log
'
