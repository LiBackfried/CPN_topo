#!/bin/bash
#SBATCH --job-name=N4_robustness
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=24:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# == 1 ]] || fail "Usage: sbatch $0 90|120"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
case "$1" in
    90) lattice=90; updates=210000; beta=0.95; proposals=48600
        ns_ids=(22810844 22810845 22810846); mc_id=22635137
        mc_group=mcmc_90_N4_beta0p95_3x100k ;;
    120) lattice=120; updates=300000; beta=1.0; proposals=86400
         ns_ids=(22885157 22904262 22904264); mc_id=22780263
         mc_group=mcmc_120_N4_beta1p0_3x100k ;;
    *) fail 'Lattice must be 90 or 120.' ;;
esac
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
roots=()
for id in "${ns_ids[@]}"; do
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L$lattice/job_$id"
    [[ -f "$root/completed" && $(<"$root/lattice") == "$lattice" && $(<"$root/tasks") == 4 ]] || fail "Expected four completed L$lattice streams: $root"
    roots+=("$root")
    for run in 0 1 2 3; do
        awk -v L="$lattice" -v p="$proposals" '
            NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
            END {exit !(v["size"]==L && w["size"]==L && v["beta"]==0.7 && v["theta"]==0 &&
                        v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==p &&
                        v["num_MC_step"]==20 && v["meas_every"]==8 &&
                        v["num_cool_step"]==50 && v["meas_cool_every"]==5)}' \
            "$root/run_$run/input.conf" || fail "Unexpected NS settings in $root/run_$run"
    done
done
mcmc="$scratch/$mc_group/job_$mc_id"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == "$lattice" && $(<"$mcmc/tasks") == 3 ]] || fail "Expected three completed MCMC chains: $mcmc"
for run in 0 1 2; do
    awk -v L="$lattice" -v b="$beta" '
        NF && $1 !~ /^#/ {v[$1]=$2; w[$1]=$3}
        END {exit !(v["size"]==L && w["size"]==L && v["beta"]==b && v["theta"]==0 &&
                    v["num_MC_step"]==1000000 && v["meas_every"]==10 &&
                    v["num_cool_step"]==50 && v["meas_cool_every"]==5)}' \
        "$mcmc/run_$run/input.conf" || fail "Unexpected MCMC settings in $mcmc/run_$run"
done
# The Python loader checks all parent segments, cumulative depths, seeds,
# repeated boundaries, N=4 logs and compatible settings before bootstrapping.
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
bootstrap=${ROBUSTNESS_BOOTSTRAP:-200}
joint_draws=${ROBUSTNESS_JOINT_DRAWS:-1000}
[[ $bootstrap =~ ^[0-9]+$ && $joint_draws =~ ^[0-9]+$ ]] || fail 'Bootstrap counts must be integers.'
(( bootstrap >= 2 && joint_draws >= 2 )) || fail 'Use at least two replicates.'
mkdir -p "$repo/N4_L${lattice}_res"
results=$(cd "$repo/N4_L${lattice}_res" && pwd -P)
[[ $results == "$repo/N4_L${lattice}_res" ]] || fail 'Output must resolve inside the repository result folder.'
output="$results/robustness_steps12_${SLURM_JOB_ID}"
record="$results/robustness_record_${SLURM_JOB_ID}"
mkdir "$record"
printf 'kind\tjob_id\tdirectory\n' > "$record/inputs.tsv"
for i in 0 1 2; do printf 'ns\t%s\t%s\n' "${ns_ids[$i]}" "${roots[$i]}" >> "$record/inputs.tsv"; done
printf 'mcmc\t%s\t%s\n' "$mc_id" "$mcmc" >> "$record/inputs.tsv"
git rev-parse HEAD > "$record/git_revision.txt"
git status --short > "$record/git_status.txt"
sha256sum N4_volume_benchmark/{check_ensemble_robustness.py,compare_action_bins.py,scan_depth.py,robustness_L90_L120_ubelix.sh} \
    analyze_nested_sampling.py utils/{nest_sampl.py,mcmc.py,cpn_io.py} > "$record/source_sha256.txt"
sha256sum "${BASH_SOURCE[0]}" >> "$record/source_sha256.txt"
printf 'SLURM_JOB_ID=%s\nL=%s\nBOOTSTRAP=%s\nJOINT_DRAWS=%s\nOUTPUT=%s\n' \
    "$SLURM_JOB_ID" "$lattice" "$bootstrap" "$joint_draws" "$output" > "$record/settings.txt"
"$python_exec" -c 'import sys,numpy,scipy,matplotlib; print(sys.version); print(numpy.__version__,scipy.__version__,matplotlib.__version__)' > "$record/python_versions.txt"
echo "L$lattice: checking both robustness steps; writing $output"
srun --export=ALL "$python_exec" -u N4_volume_benchmark/check_ensemble_robustness.py \
    --ns "${roots[@]}" --mcmc "$mcmc" --output "$output" \
    --updates "$updates" --beta "$beta" --burn-in 20000 \
    --bins 8 16 32 --blocks 128 512 1024 --baseline-bins 32 --baseline-block 512 \
    --bootstrap "$bootstrap" --joint-draws "$joint_draws" --seed 20261121
[[ -f "$output/completed" ]] || fail 'Analysis did not write its completion marker.'
touch "$record/completed"
echo "Completed L$lattice checks: $output"
