#!/bin/bash
#SBATCH -J N4L22_b07_400_799
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --array=0-15
#SBATCH --ntasks=25
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=02:00:00
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
export run_group="ns_constraint_22_N4_beta0p7_10x50000_stoc1500"
export config_dir="$project_dir/N4_L22_runs/$run_group"
export executable="$project_dir/cpn_ns_N4"

array_index="${SLURM_ARRAY_TASK_ID:?Missing SLURM_ARRAY_TASK_ID}"
export first_run_id=$((400 + 25 * array_index))
last_run_id=$((first_run_id + 24))
export output_root="/scratch/network/users/lb25v444/out_data/${run_group}/job_${SLURM_JOB_ID}"

[[ -x "$executable" ]] || {
    echo "Missing executable: $executable" >&2
    echo "Run $config_dir/build_cpn_ns_N4_ubelix.sh first." >&2
    exit 1
}

compile_info="$("$executable" 2>&1 || true)"
grep -q 'Compiled with N = 4' <<< "$compile_info" || {
    echo "$executable was not compiled with N=4." >&2
    exit 1
}

declare -A seen_seeds=()
for ((run = first_run_id; run <= last_run_id; run++)); do
    config="$config_dir/run_$run"
    [[ -r "$config" ]] || {
        echo "Missing config: $config" >&2
        exit 1
    }

    grep -Eq '^size[[:space:]]+22[[:space:]]+22([[:space:]]|$)' "$config" || {
        echo "Wrong lattice size in $config" >&2
        exit 1
    }
    grep -Eq '^beta[[:space:]]+0\.7([[:space:]]|$)' "$config" || {
        echo "Wrong beta in $config" >&2
        exit 1
    }
    grep -Eq '^num_micro[[:space:]]+4([[:space:]]|$)' "$config" || {
        echo "Wrong microcanonical-sweep count in $config" >&2
        exit 1
    }
    grep -Eq '^num_norm[[:space:]]+1([[:space:]]|$)' "$config" || {
        echo "Wrong normalization interval in $config" >&2
        exit 1
    }
    grep -Eq '^start[[:space:]]+1([[:space:]]|$)' "$config" || {
        echo "Config is not a fresh start: $config" >&2
        exit 1
    }
    grep -Eq '^rng_start[[:space:]]+0([[:space:]]|$)' "$config" || {
        echo "Config is not using a fresh RNG state: $config" >&2
        exit 1
    }
    grep -Eq '^num_single_site_stoc_upd[[:space:]]+1500([[:space:]]|$)' "$config" || {
        echo "Wrong stochastic-update count in $config" >&2
        exit 1
    }
    grep -Eq '^num_live_pts[[:space:]]+50([[:space:]]|$)' "$config" || {
        echo "Wrong live-point count in $config" >&2
        exit 1
    }
    grep -Eq '^num_ns_meas[[:space:]]+50001([[:space:]]|$)' "$config" || {
        echo "Wrong NS measurement count in $config" >&2
        exit 1
    }

    seed="$(awk '$1 == "rng_seed" {print $2}' "$config")"
    [[ "$seed" =~ ^[1-9][0-9]*$ ]] || {
        echo "Invalid or missing RNG seed in $config" >&2
        exit 1
    }
    [[ -z "${seen_seeds[$seed]+present}" ]] || {
        echo "Duplicate RNG seed $seed in $config" >&2
        exit 1
    }
    seen_seeds[$seed]=1
done

mkdir -p "$output_root"
echo "Launching 25 fresh CP^3 chains (run IDs $first_run_id through $last_run_id) in $output_root"
echo "Each chain: L=22, beta=0.7, 50 live points, 1500 stochastic updates/NS update, 50000 NS updates"

srun --ntasks=25 --cpus-per-task=1 --kill-on-bad-exit=1 --export=ALL /bin/bash -c '
set -euo pipefail
run_id=$((SLURM_PROCID + first_run_id))
outdir="$output_root/run_${run_id}"
mkdir -p "$outdir"
cp "$config_dir/run_${run_id}" "$outdir/input.conf"
cd "$outdir"
exec "$executable" input.conf > stdout.log 2> stderr.log
'
