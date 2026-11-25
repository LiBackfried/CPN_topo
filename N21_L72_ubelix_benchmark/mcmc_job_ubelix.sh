#!/bin/bash
# Submit via submit_mcmc_ubelix.sh, which sets the allocation for each role.
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --no-requeue
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail
export LC_ALL=C OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_CPUS_PER_TASK:-} == 1 ]] ||
    { echo 'Submit through sbatch with one CPU per task.' >&2; exit 1; }
role=$1 mode=$2 campaign=$(cd "$3" && pwd -P)
snapshot="$campaign/snapshot"
(cd "$snapshot"; sha256sum -c sources.sha256)
module purge
if [[ $role == analyze ]]; then
    [[ $# == 4 && $SLURM_NTASKS == 1 && $4 =~ ^[0-9]+$ ]]
    module load Python SciPy-bundle
    python_bin=$(type -P python3 || type -P python)
    results="${SLURM_SUBMIT_DIR:?Submit from the repo root.}/N21_benchmark_results"
    [[ -d $results ]]
    srun --input=none --export=ALL --ntasks=1 --cpus-per-task=1 "$python_bin" "$snapshot/analyze_mcmc.py" \
        "$mode" "$campaign/job_$4" "$results/mcmc_${mode}_$SLURM_JOB_ID"
    exit
fi
[[ $role == run && $# == 7 && $SLURM_NTASKS == 4 ]]
lattice=$4 beta=$5 steps=$6 stride=$7
case "$mode:$lattice:$beta:$stride" in
    L72-b061:72:0.61:10|L72-b060:72:0.60:1|L150-timing:150:0.60:1|L150-prior:150:0.60:1) ;;
    *) echo 'Mismatch between mode and simulation parameters.' >&2; exit 1 ;;
esac
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] && (( steps % stride == 0 ))
base_seed=$((100000000 + 4*SLURM_JOB_ID))
(( base_seed+3 < 2147483399 ))
module load OpenSSL/1.1
out="$campaign/job_$SLURM_JOB_ID"
mkdir "$out"
for task in {0..3}; do
    mkdir "$out/run_$task"
    cat > "$out/run_$task/input.conf" <<EOF
size $lattice $lattice
beta $beta
theta 0.0
num_MC_step $steps
meas_every $stride
num_micro 4
num_norm 1
save_conf_every 1000
num_cool_step 50
meas_cool_every 5
start 1
rng_seed $((base_seed+task))
rng_start 0
num_replica 1
defect_size 0
hierarc_upd 0
conf_file conf.dat
data_file dati.dat
topo_file topo.dat
log_file log.dat
rng_state_file rng_state.dat
EOF
done
srun --input=none --export=ALL --ntasks=4 --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 \
    bash -c '
        set -euo pipefail
        cd "$1/run_$SLURM_PROCID"
        hostname > node.txt
        awk -F ": " "/^model name/ {print \$2; exit}" /proc/cpuinfo >> node.txt
        /usr/bin/time -f "elapsed_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M" \
            -o timing.txt "$2" input.conf > stdout.log 2> stderr.log
        awk -v n="$3" -v stride="$4" '\''
            !/^#/ {if ($1!=++rows*stride) bad=1}
            END {exit (bad || rows!=n)}'\'' dati.dat
        awk -v n="$3" -v stride="$4" '\''
            !/^#/ {if ($1!=(int(rows/11)+1)*stride || $2!=5*(rows%11)) bad=1; rows++}
            END {exit (bad || rows!=11*n)}'\'' topo.dat
        [[ -s rng_state.dat && -s conf.dat ]]
        grep -Fxq "Theory: 2d CP^{N-1} model with N = 21" log.dat
        touch completed
    ' bash "$out" "$snapshot/cpn_N21" "$((steps/stride))" "$stride"
touch "$out/completed"
echo "Completed four $mode MCMC chains: $out"
