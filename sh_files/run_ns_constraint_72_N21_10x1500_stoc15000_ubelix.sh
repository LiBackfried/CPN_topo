#!/bin/bash
#SBATCH -J N21_ns_15k_cont
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=10:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    echo "Submit this script with sbatch (not bash or ./script)." >&2
    exit 1
fi

# The initial job ID identifies the existing scratch checkpoint directory.
initial_job_id="${1:-17336277}"
if [[ $# -gt 1 || ! "$initial_job_id" =~ ^[0-9]+$ ]]; then
    echo "Usage: sbatch run_ns_constraint_72_N21_10x1500_stoc15000_ubelix.sh INITIAL_JOB_ID" >&2
    exit 1
fi

module load OpenSSL/1.1
trap 'module purge' EXIT

export project_dir="$PWD"
export run_group="ns_constraint_72_N21_10x1500_stoc15000"
export output_root="/scratch/network/users/lb25v444/out_data/${run_group}/job_${initial_job_id}"

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

# Validate every checkpoint before starting any chain.
for run in {0..9}; do
    outdir="$output_root/run_$run"
    for file in rng_state.dat live_energy.dat conf.dat_live_{0..49}; do
        [[ -s "$outdir/$file" ]] || {
            echo "Missing checkpoint: $outdir/$file" >&2
            exit 1
        }
    done
done

echo "Continuing 10 chains in $output_root"
echo "Each chain: 50 live points, 15000 stochastic updates/NS update, 2000 additional NS updates"

srun --ntasks=10 --cpus-per-task=1 --export=ALL /bin/bash -c '
set -euo pipefail
run_id="$SLURM_PROCID"
outdir="$output_root/run_${run_id}"
[[ -d "$outdir" ]]
cp "$project_dir/config_files/$run_group/run_${run_id}" "$outdir/input_resume_${SLURM_JOB_ID}.conf"
cd "$outdir"
if [[ -f log.dat ]]; then
    cp log.dat "log_before_resume_${SLURM_JOB_ID}.dat"
fi
exec "$project_dir/cpn_ns" "input_resume_${SLURM_JOB_ID}.conf" >> stdout.log 2>> stderr.log
'
