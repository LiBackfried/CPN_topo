#!/bin/bash
#SBATCH --job-name=N4L120_sampling_validation
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=06:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
fail() { echo "$*" >&2; exit 1; }
[[ $# -ge 2 && ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch: source PILOT_ID or proposals LEAF1 LEAF2.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Results must resolve inside N4_L120_res.'
case "$1" in
    source)
        [[ $# == 2 && $2 =~ ^[0-9]+$ ]] || fail 'Use source PILOT_ID.'
        root="$scratch/mcmc_120_N4_beta0p7_initpilot/job_$2"
        [[ -f "$root/completed" ]] || fail "Missing completed source pilot: $root"
        output="$results/source_init_${2}_analysis_$SLURM_JOB_ID"
        srun --export=ALL "$python_exec" -u N4_volume_benchmark/analyze_sampling_validation.py source \
            --mcmc "$root" --output "$output"
        ;;
    proposals)
        [[ $# == 3 && $2 =~ ^[0-9]+$ && $3 =~ ^[0-9]+$ && $2 != "$3" ]] || fail 'Use proposals LEAF1 LEAF2.'
        baseline=() control=()
        for id in 22885157 22904262 22904264 23350703 23350705 23350707; do
            root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
            [[ -f "$root/completed" && $(<"$root/tasks") == 4 && $(<"$root/lattice") == 120 ]] || fail "Wrong baseline: $root"
            baseline+=("$root")
        done
        for id in "$2" "$3"; do
            root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
            [[ -f "$root/completed" && $(<"$root/tasks") == 4 && $(<"$root/lattice") == 120 ]] || fail "Wrong control: $root"
            control+=("$root")
        done
        mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
        [[ -f "$mcmc/completed" ]] || fail 'MCMC reference is incomplete.'
        output="$results/proposals172800_${2}_analysis_$SLURM_JOB_ID"
        srun --export=ALL "$python_exec" -u N4_volume_benchmark/analyze_sampling_validation.py proposals \
            --baseline "${baseline[@]}" --control "${control[@]}" --mcmc "$mcmc" \
            --output "$output" --bootstrap 200 --joint-draws 1000 --seed 20261125
        ;;
    *) fail 'Choose source or proposals.' ;;
esac
sha256sum N4_volume_benchmark/{analyze_sampling_validation.py,check_ensemble_robustness.py,scan_stream_count.py,scan_depth.py,compare_action_bins.py} \
    analyze_nested_sampling.py utils/{nest_sampl.py,mcmc.py,cpn_io.py} > "$output/source_sha256.txt"
git rev-parse HEAD > "$output/git_revision.txt"
echo "Saved sampling-validation results: $output"
