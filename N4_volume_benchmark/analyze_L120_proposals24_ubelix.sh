#!/bin/bash
#SBATCH --job-name=N4L120_p172800_24_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=08:00:00
#SBATCH --no-requeue
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 4 && ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 && ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch: NEW_LEAF1 NEW_LEAF2 NEW_LEAF3 NEW_LEAF4.'
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from CPN_topo.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
declare -A seen=([22885157]=1 [22904262]=1 [22904264]=1 [23350703]=1 [23350705]=1 [23350707]=1 [23502237]=1 [23502240]=1)
for id in "$@"; do [[ $id =~ ^[0-9]+$ && ! -v seen[$id] ]] || fail 'Use four distinct fresh leaf IDs.'; seen[$id]=1; done
baseline=() control=()
for id in 22885157 22904262 22904264 23350703 23350705 23350707 23502237 23502240 "$@"; do
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    [[ -f "$root/completed" && $(<"$root/tasks") == 4 && $(<"$root/lattice") == 120 ]] || fail "Wrong completed input: $root"
    if (( ${#baseline[@]} < 6 )); then baseline+=("$root"); else control+=("$root"); fi
done
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
[[ -f "$mcmc/completed" ]] || fail 'Expected completed reference MCMC 22780263.'
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
export LC_ALL=C MPLBACKEND=Agg OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
"$python_exec" -c 'import numpy, scipy, matplotlib'
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Results must resolve inside N4_L120_res.'
output="$results/proposals172800_24streams_analysis_$SLURM_JOB_ID"
mkdir "$output"
srun --export=ALL "$python_exec" -u N4_volume_benchmark/analyze_sampling_validation.py proposals \
    --baseline "${baseline[@]}" --control "${control[@]}" --control-streams 24 --stream-orderings 4 \
    --mcmc "$mcmc" --output "$output/proposal_comparison" --bootstrap 200 --joint-draws 1000 --seed 20261126
srun --export=ALL "$python_exec" -u N4_volume_benchmark/plot_L120_proposal_charges.py analyze \
    --comparison "$output/proposal_comparison/inputs.json" --scratch-root "$scratch" \
    --output "$output/charge_distributions" --bootstrap 200 --seed 20261126
sha256sum N4_volume_benchmark/{analyze_sampling_validation.py,plot_L120_proposal_charges.py,plot_charge_distributions.py,export_charge_moments.py,check_ensemble_robustness.py,scan_stream_count.py,scan_depth.py,compare_action_bins.py} \
    analyze_nested_sampling.py utils/{nest_sampl.py,mcmc.py,cpn_io.py} > "$output/source_sha256.txt"
git rev-parse HEAD > "$output/git_revision.txt"
touch "$output/completed"
echo "Completed matched 24-stream proposal comparison, old8/fresh16 checks, depth/count scans and charge distributions: $output"
