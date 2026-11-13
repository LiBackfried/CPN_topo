#!/bin/bash
#SBATCH --job-name=N4L38_b10_mcmc
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=3
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=03:00:00
#SBATCH --no-requeue

set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 3 &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and request three tasks with one CPU each.'

project=${SLURM_SUBMIT_DIR:?Submit from the CPN_topo repository root.}
group=mcmc_38_N4_beta1p0_3x100k
config_dir="$project/N4_volume_benchmark/$group"
executable="$project/cpn_N4"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
output_root="$scratch/$group/job_${SLURM_JOB_ID}"
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
[[ -x $executable ]] || fail 'Build cpn_N4 using the N=4 MCMC build helper first.'
[[ -x /usr/bin/time ]] || fail 'GNU time is required at /usr/bin/time.'
module load OpenSSL/1.1
compile_info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$compile_info" || fail 'cpn_N4 did not report N=4.'

expected_settings=(
    'size 38 38' 'beta 1.0' 'theta 0.0'
    'num_MC_step 1000000' 'meas_every 10' 'num_micro 4' 'num_norm 1'
    'save_conf_every 1000' 'num_cool_step 50' 'meas_cool_every 5'
    'start 1' 'rng_start 0' 'num_replica 1' 'defect_size 0' 'hierarc_upd 0'
    'conf_file conf.dat' 'data_file dati.dat' 'topo_file topo.dat'
    'log_file log.dat' 'rng_state_file rng_state.dat'
)
declare -A seen_seeds=()
for run in {0..2}; do
    config="$config_dir/run_$run.conf"
    [[ -r $config ]] || fail "Missing config $config"
    diff -u <(printf '%s\n' "${expected_settings[@]}" | sort) \
        <(awk '{ sub(/#.*/, ""); if (NF && $1 != "rng_seed") { $1 = $1; print } }' "$config" | sort) ||
        fail "Unexpected settings in $config"
    seed=$(awk '$1 == "rng_seed" { print $2 }' "$config")
    [[ $seed =~ ^[1-9][0-9]{0,9}$ ]] && (( seed < 2147483399 )) && [[ ! -v seen_seeds[$seed] ]] ||
        fail "Invalid or duplicate RNG seed in $config"
    seen_seeds[$seed]=1
done

mkdir -p "$(dirname "$output_root")"
mkdir "$output_root"
cp "$executable" "$output_root/cpn_N4"
for run in {0..2}; do
    mkdir "$output_root/run_$run"
    cp "$config_dir/run_$run.conf" "$output_root/run_$run/input.conf"
done

echo "Launching three L=38, beta=1.0 chains in $output_root"
srun --ntasks=3 --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 --export=ALL /bin/bash -c '
    set -euo pipefail
    cd "$1/run_$SLURM_PROCID"
    hostname > node.txt
    awk -F ": " "/^model name/ {print \$2; exit}" /proc/cpuinfo >> node.txt
    LC_ALL=C /usr/bin/time -f "elapsed_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M" \
        -o timing.txt "$1/cpn_N4" input.conf > stdout.log 2> stderr.log
    awk "!/^#/ {n++} END {exit (n != 100000)}" dati.dat
    awk "!/^#/ {n++} END {exit (n != 1100000)}" topo.dat
' bash "$output_root"
touch "$output_root/completed"
