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
# This also verifies both completed jobs, all streams and the distinct seed ranges.
"$python_bin" "$snapshot/summarize.py" "$campaign" "$output"
while IFS=$'\t' read -r proposals steps seed_base job path; do
    [[ $proposals == proposals ]] && continue
    srun --ntasks=1 --cpus-per-task=1 --export=ALL "$python_bin" "$snapshot/analyze_nested_sampling.py" \
        "$path" --output "$output/p${proposals}" --cpn-n 21 --bootstrap 500 --seed 20261124 \
        > "$output/p${proposals}_analysis.log" 2>&1
done < "$campaign/jobs.tsv"
"$python_bin" "$snapshot/summarize.py" "$campaign" "$output" --compare-observables
touch "$output/completed"
echo "Completed N21 timing and weighted source-beta analyses: $output"
