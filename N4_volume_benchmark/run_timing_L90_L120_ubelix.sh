#!/bin/bash
# Batch worker used by benchmark_L90_L120_ubelix.sh; submit with sbatch.
#SBATCH --job-name=N4_large_timing
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=00:45:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# == 6 ]] || fail "Usage: sbatch $0 KIND L STEPS PROPOSALS SEED_BASE CAMPAIGN"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 4 &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Request four tasks with one CPU each using sbatch.'
kind=$1 L=$2 steps=$3 stoc=$4 seed_base=$5 campaign=$6
[[ $kind == ns || $kind == mcmc ]] || fail 'KIND must be ns or mcmc.'
case $L in 90) target=0.95 ;; 120) target=1.0 ;; *) fail 'L must be 90 or 120.' ;; esac
[[ $steps =~ ^[1-9][0-9]{0,6}$ && $seed_base =~ ^[1-9][0-9]{0,9}$ ]] || fail 'Invalid step count or seed base.'
(( seed_base + 3 < 2147483399 )) || fail 'Seeds exceed the ran2 range.'
[[ $campaign == /* && -d $campaign ]] || fail 'CAMPAIGN must be an existing absolute directory.'
campaign=$(cd "$campaign" && pwd -P)
if [[ $kind == ns ]]; then
    [[ $stoc == "$((3*L*L))" || $stoc == "$((6*L*L))" ]] || fail 'NS proposals must equal 3L^2 or 6L^2.'
    beta=0.7 executable="$campaign/bin/cpn_ns_N4"
else
    [[ $stoc == 0 ]] && (( steps % 10 == 0 )) || fail 'MCMC needs PROPOSALS=0 and a multiple of ten steps.'
    beta=$target executable="$campaign/bin/cpn_N4"
fi
template="$campaign/templates/$kind.conf"
[[ -x $executable && -r $template && -x /usr/bin/time ]] || fail 'Missing executable, template or GNU time.'
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info" || fail 'Expected an N=4 executable.'
output="$campaign/${kind}_L${L}_stoc${stoc}_${steps}/job_${SLURM_JOB_ID}"
mkdir -p "$(dirname "$output")"
mkdir "$output"  # Refuse existing outputs, including manual requeues.
cp "$executable" "$output/executable"
printf '%s\n' "$L" > "$output/lattice"
printf '4\n' > "$output/tasks"
for run in 0 1 2 3; do
    mkdir "$output/run_$run"
    awk -v kind="$kind" -v l="$L" -v beta="$beta" -v steps="$steps" \
        -v stoc="$stoc" -v seed="$((seed_base+run))" '
        /^#/ {next}
        $1=="size" {print $1,l,l; next}
        $1=="beta" {print $1,beta; next}
        $1=="rng_seed" {print $1,seed; next}
        $1=="num_ns_meas" {print $1,steps+1; next}
        $1=="num_single_site_stoc_upd" {print $1,stoc; next}
        $1=="num_MC_step" {print $1,(kind=="ns" ? 20 : steps); next}
        $1=="meas_every" {print $1,(kind=="ns" ? 8 : 10); next}
        {print}
    ' "$template" > "$output/run_$run/input.conf"
    awk -v kind="$kind" -v l="$L" -v beta="$beta" -v steps="$steps" -v stoc="$stoc" -v seed="$((seed_base+run))" '
        NF && $1 !~ /^#/ {if (seen[$1]++) bad=1; v[$1]=$2; w[$1]=$3}
        END {
            ok=(!bad && v["size"]==l && w["size"]==l && v["beta"]==beta &&
                v["theta"]==0 && v["rng_seed"]==seed && v["start"]==1 && v["rng_start"]==0 &&
                v["num_micro"]==4 && v["num_norm"]==1 && v["num_cool_step"]==50 &&
                v["meas_cool_every"]==5 && v["num_replica"]==1 && v["defect_size"]==0 &&
                v["hierarc_upd"]==0 && v["conf_file"]=="conf.dat" && v["log_file"]=="log.dat" &&
                v["data_file"]=="dati.dat" && v["topo_file"]=="topo.dat" && v["rng_state_file"]=="rng_state.dat")
            if (kind=="ns") ok=ok && v["num_ns_meas"]==steps+1 && v["num_live_pts"]==50 &&
                v["num_single_site_stoc_upd"]==stoc && v["num_MC_step"]==20 && v["meas_every"]==8 &&
                v["save_conf_every"]==1 && v["save_dead"]==0 && v["live_energy_file"]=="live_energy.dat"
            else ok=ok && v["num_MC_step"]==steps && v["meas_every"]==10 && v["save_conf_every"]==1000
            exit !ok
        }
    ' "$output/run_$run/input.conf" || fail "Invalid generated config: $output/run_$run/input.conf"
done
srun --export=ALL --ntasks=4 --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 /bin/bash -c '
    set -euo pipefail
    output=$1 kind=$2 steps=$3
    cd "$output/run_$SLURM_PROCID"
    hostname > node.txt
    awk -F ": " "/^model name/ {print \$2; exit}" /proc/cpuinfo >> node.txt
    /usr/bin/time -f "elapsed_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M" \
        -o timing.txt "$output/executable" input.conf > stdout.log 2> stderr.log
    if [[ $kind == ns ]]; then
        rows=$((steps+1))
        awk -v n="$steps" "NF && \$1 !~ /^#/ {if (\$1 != ++i) bad=1} END {exit (bad || i != n)}" acceptance_rate.dat
        [[ -s live_energy.dat && -s rng_state.dat ]]
        for live in {0..49}; do [[ -s conf.dat_live_$live ]]; done
    else
        rows=$((steps/10))
        [[ -s conf.dat && -s rng_state.dat ]]
    fi
    awk -v n="$rows" "NF && \$1 !~ /^#/ {i++} END {exit (i != n)}" dati.dat
    awk -v n="$((11*rows))" "NF && \$1 !~ /^#/ {i++} END {exit (i != n)}" topo.dat
    du -sb . | awk "{print \$1}" > output_bytes.txt
' bash "$output" "$kind" "$steps"
touch "$output/completed"
echo "Completed $kind L=$L beta=$beta steps=$steps proposals=$stoc: $output"
