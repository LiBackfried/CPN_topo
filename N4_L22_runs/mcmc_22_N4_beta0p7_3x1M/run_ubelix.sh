#!/bin/bash
#SBATCH --job-name=N4L22_b07_mcmc
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=3
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=04:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" || "${SLURM_NTASKS:-}" != 3 || "${SLURM_CPUS_PER_TASK:-}" != 1 ]]; then
    echo 'Submit with sbatch and request three tasks with one CPU each.' >&2
    exit 1
fi

module load OpenSSL/1.1

run_group="mcmc_22_N4_beta0p7_3x1M"
config_dir="$PWD/N4_L22_runs/$run_group"
executable="$PWD/cpn_N4"
scratch_group="/scratch/network/users/lb25v444/out_data/$run_group"
output_root="$scratch_group/job_${SLURM_JOB_ID}"

if [[ ! -x "$executable" ]]; then
    echo "Missing executable $executable. Run $config_dir/build_cpn_N4_ubelix.sh with bash first." >&2
    exit 1
fi

compile_info="$("$executable" 2>&1 || true)"
if ! grep -Fxq 'Compiled with N = 4' <<< "$compile_info"; then
    echo "$executable did not report N=4." >&2
    exit 1
fi

expected_settings=(
    'size 22 22' 'beta 0.7' 'theta 0.0'
    'num_MC_step 10000000' 'meas_every 10' 'num_micro 4' 'num_norm 1'
    'save_conf_every 1000' 'num_cool_step 50' 'meas_cool_every 5'
    'start 1' 'rng_start 0' 'num_replica 1' 'defect_size 0' 'hierarc_upd 0'
    'conf_file conf.dat' 'data_file dati.dat' 'topo_file topo.dat'
    'log_file log.dat' 'rng_state_file rng_state.dat'
)
declare -A seen_seeds=()
for run in {0..2}; do
    config="$config_dir/run_$run.conf"
    if [[ ! -r "$config" ]]; then
        echo "Missing config $config" >&2
        exit 1
    fi
    if ! diff -u <(printf '%s\n' "${expected_settings[@]}" | sort) \
        <(awk '{ sub(/#.*/, ""); if (NF && $1 != "rng_seed") { $1 = $1; print } }' "$config" | sort); then
        echo "Unexpected settings in $config" >&2
        exit 1
    fi
    seed="$(awk '$1 == "rng_seed" { print $2 }' "$config")"
    if [[ ! "$seed" =~ ^[1-9][0-9]*$ || -n "${seen_seeds[$seed]:-}" ]]; then
        echo "Invalid or duplicate RNG seed in $config" >&2
        exit 1
    fi
    seen_seeds[$seed]=1
done

mkdir -p "$scratch_group"
# Fail if this job's directory exists to avoid appending to a previous chain.
mkdir "$output_root"
for run in {0..2}; do
    outdir="$output_root/run_$run"
    mkdir "$outdir"
    cp "$config_dir/run_$run.conf" "$outdir/input.conf"
done

echo "Launching three CP^3 chains with 10,000,000 MC steps each in $output_root"
srun --ntasks=3 --cpus-per-task=1 --kill-on-bad-exit=0 --export=ALL /bin/bash -c '
    set -euo pipefail
    cd "$1/run_${SLURM_PROCID}"
    exec "$2" input.conf > stdout.log 2> stderr.log
' bash "$output_root" "$executable"
