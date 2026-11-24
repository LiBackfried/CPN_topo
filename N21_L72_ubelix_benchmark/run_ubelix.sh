#!/bin/bash
#SBATCH --job-name=N21_L72_benchmark
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=02:00:00
#SBATCH --no-requeue
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail
export LC_ALL=C OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# == 4 ]] || fail "Usage: sbatch $0 PROPOSALS UPDATES SEED_BASE CAMPAIGN"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 10 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] ||
    fail 'Submit with sbatch requesting ten tasks and one CPU per task.'
proposals=$1 steps=$2 seed_base=$3 campaign=$4
[[ $proposals == 15500 || $proposals == 31000 ]] || fail 'Choose 15500 or 31000 proposals.'
[[ $steps =~ ^[1-9][0-9]{0,6}$ && $seed_base =~ ^[1-9][0-9]{0,9}$ ]] &&
    (( seed_base + 9 < 2147483399 )) || fail 'Invalid update count or seed range.'
[[ $campaign == /* && -d $campaign/snapshot ]] || fail 'Missing absolute campaign snapshot.'
campaign=$(cd "$campaign" && pwd -P)
snapshot="$campaign/snapshot"
module purge
module load OpenSSL/1.1
executable="$snapshot/cpn_ns_N21"
[[ -x $executable && -x /usr/bin/time ]] || fail 'Missing N21 executable or GNU time.'
sha256sum -c "$snapshot/executable.sha256"
(cd "$snapshot"; sha256sum -c scripts.sha256)
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info" || fail 'Expected N=21.'
output="$campaign/job_${SLURM_JOB_ID}"
mkdir "$output"  # Refuse previous outputs, including a manual requeue.
printf '%s\n' "$info" > "$output/executable_banner.txt"
env | LC_ALL=C sort | awk '/^SLURM_(JOB_ID|NTASKS|CPUS_PER_TASK|JOB_CPUS_PER_NODE|JOB_NODELIST)=/' > "$output/allocation.txt"
for run in {0..9}; do
    mkdir "$output/run_$run"
    awk -v stoc="$proposals" -v meas="$((steps+1))" -v seed="$((seed_base+run))" '
        /^#/ {next}
        $1=="rng_seed" {print $1,seed; next}
        $1=="num_ns_meas" {print $1,meas; next}
        $1=="num_single_site_stoc_upd" {print $1,stoc; next}
        {print}
    ' "$snapshot/input.template" > "$output/run_$run/input.conf"
    awk -v stoc="$proposals" -v meas="$((steps+1))" -v seed="$((seed_base+run))" '
        NF && $1 !~ /^#/ {if (seen[$1]++) bad=1; v[$1]=$2; w[$1]=$3}
        END {exit !(!bad && v["size"]==72 && w["size"]==72 && v["beta"]==0.6 && v["theta"]==0 &&
            v["start"]==1 && v["rng_start"]==0 && v["rng_seed"]==seed && v["num_ns_meas"]==meas &&
            v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==stoc && v["num_micro"]==4 &&
            v["num_norm"]==1 && v["num_MC_step"]==20 && v["meas_every"]==8 &&
            v["num_cool_step"]==50 && v["meas_cool_every"]==5 && v["save_dead"]==0 &&
            v["num_replica"]==1 && v["defect_size"]==0 && v["hierarc_upd"]==0 &&
            v["save_conf_every"]==1 && v["conf_file"]=="conf.dat" && v["data_file"]=="dati.dat" &&
            v["topo_file"]=="topo.dat" && v["live_energy_file"]=="live_energy.dat" &&
            v["rng_state_file"]=="rng_state.dat" && v["log_file"]=="log.dat")}
    ' "$output/run_$run/input.conf" || fail "Invalid config for run_$run."
done
srun --export=ALL --ntasks=10 --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 /bin/bash -c '
    set -euo pipefail
    output=$1 executable=$2 steps=$3
    cd "$output/run_$SLURM_PROCID"
    hostname > node.txt
    awk -F ": " "/^model name/ {print \$2; exit}" /proc/cpuinfo >> node.txt
    /usr/bin/time -f "elapsed_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M" \
        -o timing.txt "$executable" input.conf > stdout.log 2> stderr.log
    awk -v n="$steps" "NF && \$1 !~ /^#/ {if (\$1 != ++i || \$2<0 || \$2>1 || \$3<0 || \$3>1) bad=1} END {exit (bad || i != n)}" acceptance_rate.dat
    awk -v n="$((steps+1))" "NF && \$1 !~ /^#/ {if (NF<4 || (i && \$2>last+1e-12)) bad=1; last=\$2; i++} END {exit (bad || i != n)}" dati.dat
    awk -v n="$((11*(steps+1)))" "NF && \$1 !~ /^#/ {if (NF<5 || \$2 != (i%11)*5) bad=1; i++} END {exit (bad || i != n)}" topo.dat
    [[ -s rng_state.dat && -s log.dat ]]
    [[ $(awk "NF && \$1 !~ /^#/ {n++} END {print n+0}" live_energy.dat) == 50 ]]
    for live in {0..49}; do
        [[ -s conf.dat_live_$live ]]
        head -n1 "conf.dat_live_$live" | awk "{exit !(\$2==21 && \$3==72 && \$4==72)}"
    done
    grep -q "^#NS loop wall time:" stdout.log
    touch completed
' bash "$output" "$executable" "$steps"
touch "$output/completed"
echo "Completed ten N21 L72 streams: $output ($steps updates, $proposals proposals/update)."
