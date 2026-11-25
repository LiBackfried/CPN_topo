#!/bin/bash
#SBATCH --job-name=N4L120_stream_count
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=32G
#SBATCH --time=24:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# == 2 ]] || fail "Usage: sbatch $0 prepare|evaluate|collect CAMPAIGN_DIRECTORY"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and one task/CPU.'
phase=$1
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
campaign=$(cd "$2" && pwd -P)
[[ $campaign == "$repo/N4_L120_res/"stream_count24.* ]] || fail 'Campaign must resolve inside repository N4_L120_res/stream_count24.*.'
[[ -s "$campaign/settings.tsv" ]] || fail 'Missing campaign settings.'
setting() { awk -F '\t' -v key="$1" '$1==key {print $2}' "$campaign/settings.tsv"; }
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
driver="$repo/N4_volume_benchmark/scan_stream_count.py"
case "$phase" in
    prepare)
        roots=()
        while IFS=$'\t' read -r kind id root; do
            [[ $kind == ns || $kind == mcmc ]] || continue
            [[ -f "$root/completed" && $(<"$root/lattice") == 120 ]] || fail "Expected completed L120 data: $root"
            if [[ $kind == ns ]]; then
                [[ $(<"$root/tasks") == 4 ]] || fail "Expected four NS streams: $root"
                roots+=("$root")
            else
                [[ $(<"$root/tasks") == 3 ]] || fail "Expected three MCMC chains: $root"
                mcmc=$root
            fi
        done < "$campaign/raw_inputs.tsv"
        [[ ${#roots[@]} == 6 && -n ${mcmc:-} ]] || fail 'Expected six NS leaf jobs and one MCMC job.'
        srun --export=ALL "$python_exec" -u "$driver" prepare --ns "${roots[@]}" --mcmc "$mcmc" \
            --output "$campaign/cache" --updates 300000 --beta 1.0 --burn-in 20000 \
            --bins 32 --block-size 512 --focus-bin 9 --counts 6 8 12 16 20 24 \
            --orderings "$(setting orderings)" --bootstrap "$(setting bootstrap)" \
            --joint-draws "$(setting joint_draws)" --seed "$(setting seed)"
        ;;
    evaluate)
        [[ ${SLURM_ARRAY_TASK_ID:-} =~ ^[0-9]+$ ]] || fail 'Evaluation must be a Slurm array task.'
        srun --export=ALL "$python_exec" -u "$driver" evaluate --cache "$campaign/cache" \
            --task "$SLURM_ARRAY_TASK_ID" --output "$campaign/evaluations/task_$SLURM_ARRAY_TASK_ID"
        ;;
    collect)
        srun --export=ALL "$python_exec" -u "$driver" collect --cache "$campaign/cache" \
            --evaluations "$campaign/evaluations" --output "$campaign/report_$SLURM_JOB_ID"
        ;;
    *) fail 'Phase must be prepare, evaluate or collect.' ;;
esac
echo "Completed $phase: $campaign"
