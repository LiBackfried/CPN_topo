#!/bin/bash
#SBATCH --job-name=N4L120_b07_initpilot
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=02:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# == 2 ]] || fail "Usage: sbatch $0 SEED_BASE MC_CYCLES"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 4 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and four single-CPU tasks.'
base=$1 steps=$2
[[ $base =~ ^[1-9][0-9]{0,9}$ ]] && (( base + 4 < 2147483399 )) || fail 'Invalid seed base.'
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] && (( steps >= 10000 )) || fail 'Use at least 10000 MC cycles.'
repo=${SLURM_SUBMIT_DIR:?Submit from CPN_topo root.}
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
executable=${MCMC_EXECUTABLE:-$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263/cpn_N4}
[[ $executable == /* && -x $executable ]] || fail 'A saved N=4 cpn executable is required.'
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'MCMC executable must report N=4.'
template="$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_0.conf"
[[ -s $template ]] || fail 'Missing MCMC template.'
output="$scratch/mcmc_120_N4_beta0p7_initpilot/job_$SLURM_JOB_ID"
mkdir -p "$(dirname "$output")"
mkdir "$output"
cp "$executable" "$output/cpn_N4"
printf '120\n' > "$output/lattice"; printf '4\n' > "$output/tasks"
sha256sum "$output/cpn_N4" > "$output/executable_sha256.txt"
printf 'run\tstart\tseed\n' > "$output/chains.tsv"
for run in 0 1 2 3; do
    if (( run < 2 )); then start=0; else start=1; fi
    seed=$((base+run))
    mkdir "$output/run_$run"
    awk -v steps="$steps" -v start="$start" -v seed="$seed" '
        /^#/ {next}
        $1=="beta" {print $1,0.7; next}
        $1=="num_MC_step" {print $1,steps; next}
        $1=="meas_every" {print $1,1; next}
        $1=="start" {print $1,start; next}
        $1=="rng_start" {print $1,0; next}
        $1=="rng_seed" {print $1,seed; next}
        {print}
    ' "$template" > "$output/run_$run/input.conf"
    awk -v steps="$steps" -v start="$start" -v seed="$seed" '
        NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
        END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                    v["num_MC_step"]==steps && v["meas_every"]==1 && v["start"]==start &&
                    v["rng_start"]==0 && v["rng_seed"]==seed && v["num_micro"]==4 &&
                    v["num_norm"]==1 && v["num_replica"]==1 && v["num_cool_step"]==50 &&
                    v["meas_cool_every"]==5)}' "$output/run_$run/input.conf" || fail 'Wrong source-pilot config.'
    printf '%s\t%s\t%s\n' "$run" "$start" "$seed" >> "$output/chains.tsv"
done
echo "Launching two cold and two hot beta=0.7 pilots, $steps MC cycles, measurement every cycle: $output"
srun --export=ALL --ntasks=4 --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 /bin/bash -c '
    set -euo pipefail
    cd "$1/run_$SLURM_PROCID"
    /usr/bin/time -f "elapsed_seconds=%e\nmax_rss_kib=%M" -o timing.txt \
        "$1/cpn_N4" input.conf > stdout.log 2> stderr.log
    awk -v n="$2" "NF && \$1 !~ /^#/ {count++} END {exit(count!=n)}" dati.dat
    awk -v n="$((11*$2))" "NF && \$1 !~ /^#/ {count++} END {exit(count!=n)}" topo.dat
    [[ -s conf.dat && -s rng_state.dat ]]
' bash "$output" "$steps"
touch "$output/completed"
