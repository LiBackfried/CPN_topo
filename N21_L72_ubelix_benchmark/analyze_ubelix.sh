#!/bin/bash
#SBATCH --job-name=N21_L72_analysis
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --no-requeue
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=END,FAIL
set -euo pipefail
export LC_ALL=C OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
[[ $# == 1 && ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || { echo "Usage: sbatch $0 CAMPAIGN (one CPU)" >&2; exit 1; }
[[ $1 == /* && -d $1/snapshot ]] || exit 1
campaign=$(cd "$1" && pwd -P)
snapshot="$campaign/snapshot"
(cd "$snapshot"; sha256sum -c scripts.sha256)
module purge
module load Python SciPy-bundle matplotlib
python_bin=$(type -P python3 || type -P python)
"$python_bin" -c 'import numpy, scipy, matplotlib'
output="$campaign/analysis_${SLURM_JOB_ID}"
mkdir "$output"
# Keep the worker actually submitted, including when repairing an older snapshot.
cp "${BASH_SOURCE[0]}" "$output/analysis_worker.sh"
sha256sum "$output/analysis_worker.sh" > "$output/analysis_worker.sha256"
# This also verifies both completed jobs, all streams and the distinct seed ranges.
"$python_bin" "$snapshot/summarize.py" "$campaign" "$output"
while IFS=$'\t' read -r -u 3 proposals steps seed_base job path; do
    [[ $proposals == proposals ]] && continue
    srun --input=none --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" "$snapshot/analyze_nested_sampling.py" \
        "$path" --output "$output/p${proposals}" --cpn-n 21 --bootstrap 500 --seed 20261124 \
        < /dev/null 3<&- > "$output/p${proposals}_analysis.log" 2>&1
    [[ -s "$output/p${proposals}/results.json" ]] || {
        echo "Analysis did not produce p${proposals}/results.json; inspect $output/p${proposals}_analysis.log" >&2
        exit 1
    }
done 3< "$campaign/jobs.tsv"
"$python_bin" "$snapshot/summarize.py" "$campaign" "$output" --compare-observables
touch "$output/completed"
echo "Completed N21 timing and weighted source-beta analyses: $output"
