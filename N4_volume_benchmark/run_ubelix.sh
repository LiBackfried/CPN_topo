#!/bin/bash
#SBATCH --job-name=N4_b07_volume
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --time=03:00:00
#SBATCH --no-requeue

set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} =~ ^[1-9][0-9]?$ &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one CPU per chain.'
(( SLURM_NTASKS <= 32 )) || fail 'Use at most 32 tasks per pilot job.'
[[ $# -ge 1 && $# -le 3 ]] || fail 'Usage: sbatch run_ubelix.sh L [updates [parent_job_dir]]'
L=$1
case $L in
    22) baseline_stoc=1500 ;;
    38|66|90|120) baseline_stoc=$((3 * L * L)) ;;
    *) fail 'L must be 22, 38, 66, 90 or 120.' ;;
esac
updates=${2:-100}
[[ $updates =~ ^[1-9][0-9]{0,8}$ ]] || fail 'Use a positive integer update count (up to nine digits).'
parent=${3:-}
resume=0
project_dir=${SLURM_SUBMIT_DIR:?Submit from the CPN_topo repository root.}
template="$project_dir/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0"
executable="$project_dir/cpn_ns_N4"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
output_root="$scratch/ns_N4_beta0p7_volume_benchmark/L${L}/job_${SLURM_JOB_ID}"
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
[[ -x /usr/bin/time ]] || fail 'GNU time is required at /usr/bin/time.'

if [[ -n $parent ]]; then
    resume=1
    parent="$(cd "$parent" && pwd -P)"
    [[ -f "$parent/completed" ]] || fail 'The parent benchmark job must have completed successfully.'
    [[ $(<"$parent/lattice") == "$L" && $(<"$parent/tasks") == "$SLURM_NTASKS" ]] ||
        fail 'Use the same L and task count as the parent job.'
    executable="$parent/cpn_ns_N4"
    [[ ! -v NS_STOC && ! -v NS_INIT_SWEEPS && ! -v NS_INIT_SPACING ]] ||
        fail 'A continuation inherits its stochastic update count and initialization settings.'
fi
[[ -r $template && -x $executable ]] || fail 'Submit from CPN_topo after building cpn_ns_N4 with the existing N=4 helper.'
module load OpenSSL/1.1
compile_info="$("$executable" 2>&1 || true)"
grep -qx 'Compiled with N = 4' <<< "$compile_info" || fail 'cpn_ns_N4 did not report N=4.'

stoc=${NS_STOC:-$baseline_stoc}
init_sweeps=${NS_INIT_SWEEPS:-20}
init_spacing=${NS_INIT_SPACING:-8}
for value in "$stoc" "$init_sweeps" "$init_spacing"; do
    [[ $value =~ ^[1-9][0-9]{0,6}$ ]] || fail 'Use positive integers for NS_STOC, NS_INIT_SWEEPS and NS_INIT_SPACING.'
done
seed_base=$((100000000 + 32 * SLURM_JOB_ID))
if [[ -z $parent ]] && (( seed_base + SLURM_NTASKS >= 2147483399 )); then
    fail 'Job-derived seeds exceed the ran2 seed range.'
fi

mkdir -p "$(dirname "$output_root")"
mkdir "$output_root"  # Refuse to reuse output, including on a manual requeue.
cp "$executable" "$output_root/cpn_ns_N4"
printf '%s\n' "$L" > "$output_root/lattice"
printf '%s\n' "$SLURM_NTASKS" > "$output_root/tasks"
declare -A seen_seeds=()
for ((run = 0; run < SLURM_NTASKS; run++)); do
    out="$output_root/run_$run"
    mkdir "$out"
    if (( resume )); then
        source_run="$parent/run_$run"
        [[ -s "$source_run/input.conf" ]] || fail "Missing config in $source_run"
        checkpoint=(live_energy.dat rng_state.dat)
        for ((live = 0; live < 50; live++)); do checkpoint+=("conf.dat_live_$live"); done
        for file in "${checkpoint[@]}"; do
            [[ -s "$source_run/$file" ]] || fail "Missing checkpoint file: $source_run/$file"
            cp "$source_run/$file" "$out/"
        done
        awk -v meas="$((updates + 1))" '
            $1 == "num_ns_meas" {print $1, meas; next}
            $1 == "start" {print $1, 2; next}
            $1 == "rng_start" {print $1, 1; next}
            {print}
        ' "$source_run/input.conf" > "$out/input.conf"
        realpath --relative-to="$out" "$source_run" > "$out/parent_run"
    else
        seed=$((seed_base + run))
        awk -v l="$L" -v seed="$seed" -v stoc="$stoc" -v meas="$((updates + 1))" \
            -v init="$init_sweeps" -v spacing="$init_spacing" '
            /^#/ {next}
            $1 == "size" {print $1, l, l; next}
            $1 == "rng_seed" {print $1, seed; next}
            $1 == "num_single_site_stoc_upd" {print $1, stoc; next}
            $1 == "num_ns_meas" {print $1, meas; next}
            $1 == "num_MC_step" {print $1, init; next}
            $1 == "meas_every" {print $1, spacing; next}
            {print}
        ' "$template" > "$out/input.conf"
    fi
    seed="$(awk -v l="$L" -v meas="$((updates + 1))" -v resume="$resume" -v stoc="$stoc" '
        $1 !~ /^#/ && NF {value[$1]=$2; second[$1]=$3}
        END {
            if (!(value["size"] == l && second["size"] == l && value["beta"] == 0.7 &&
                   value["theta"] == 0 && value["num_live_pts"] == 50 && value["num_replica"] == 1 &&
                   value["rng_seed"] ~ /^[1-9][0-9]*$/ && value["num_ns_meas"] == meas &&
                   (resume ? value["num_single_site_stoc_upd"] > 0 : value["num_single_site_stoc_upd"] == stoc) &&
                   value["num_norm"] == 1 && value["num_micro"] == 4 && value["save_dead"] == "0" &&
                   value["start"] == 1 + resume && value["rng_start"] == resume &&
                   value["conf_file"] == "conf.dat" && value["live_energy_file"] == "live_energy.dat" &&
                   value["rng_state_file"] == "rng_state.dat")) exit 1
            print value["rng_seed"]
        }
    ' "$out/input.conf")" || fail "Invalid generated config in $out"
    [[ ! -v seen_seeds[$seed] ]] || fail "Duplicate seed $seed in $out"
    seen_seeds[$seed]=1
done

export output_root
echo "L=$L, $SLURM_NTASKS chains, $updates updates per chain in $output_root"
srun --ntasks="$SLURM_NTASKS" --cpus-per-task=1 --cpu-bind=cores --kill-on-bad-exit=1 /bin/bash -c '
    set -euo pipefail
    cd "$output_root/run_$SLURM_PROCID"
    hostname > node.txt
    awk -F ": " "/^model name/ {print \$2; exit}" /proc/cpuinfo >> node.txt
    LC_ALL=C /usr/bin/time -f "elapsed_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M" \
        -o timing.txt "$output_root/cpn_ns_N4" input.conf > stdout.log 2> stderr.log
'
touch "$output_root/completed"
