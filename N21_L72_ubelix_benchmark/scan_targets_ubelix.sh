#!/bin/bash
#SBATCH --job-name=N21_L72_targets
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

[[ $# -ge 1 && $# -le 2 && ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || {
    echo "Submit from the repository root with sbatch $0 CAMPAIGN [ORIGINAL_CAMPAIGN] (one CPU)." >&2
    exit 1
}
campaign=$(cd "$1" && pwd -P)
reference=
if [[ $# == 2 ]]; then
    reference=$(cd "$2" && pwd -P)
    repo="$campaign/snapshot"
    (cd "$repo"; sha256sum -c scripts.sha256)
    cmp -s "$repo/cpn_ns_N21" "$reference/snapshot/cpn_ns_N21" || {
        echo "Expected both near-source campaigns to use the same executable." >&2
        exit 1
    }
    output="$campaign/near_source_${SLURM_JOB_ID}"
else
    repo=${SLURM_SUBMIT_DIR:?Submit from the CPN_topo repository root.}
    output="$campaign/target_scan_${SLURM_JOB_ID}"
fi
scanner="$repo/N4_volume_benchmark/scan_depth.py"
[[ -r $scanner ]]

read_completed_jobs() {
    local root=$1 expected_steps=$2 proposals steps seed_base job path stream dir
    local -n jobs_by_proposals=$3
    while IFS=$'\t' read -r proposals steps seed_base job path; do
        [[ $proposals == proposals ]] && continue
        if [[ $proposals != 15500 && $proposals != 31000 ]] ||
            [[ $steps != "$expected_steps" || ! $job =~ ^[0-9]+$ || -n ${jobs_by_proposals[$proposals]:-} ||
               ! $path -ef "$root/job_$job" || ! -f $path/completed ]]; then
            echo "Expected separate completed $expected_steps-update jobs at both proposal counts in $root." >&2
            return 1
        fi
        jobs_by_proposals[$proposals]=$path
        for stream in {0..9}; do
            dir="$path/run_$stream"
            [[ -f $dir/completed ]]
            awk -v p="$proposals" -v n="$((expected_steps+1))" '
                $1=="size" {size=($2==72 && $3==72)}
                $1=="num_live_pts" {live=($2==50)}
                $1=="num_ns_meas" {steps=($2==n)}
                $1=="num_single_site_stoc_upd" {stoc=($2==p)}
                END {exit !(size && live && steps && stoc)}
            ' "$dir/input.conf"
        done
    done < "$root/jobs.tsv"
    if [[ ${#jobs_by_proposals[@]} != 2 ]]; then
        echo "Expected two proposal-count jobs in $root/jobs.tsv." >&2
        return 1
    fi
}
declare -A job_paths reference_paths
if [[ -n $reference ]]; then
    read_completed_jobs "$campaign" 20000 job_paths
    read_completed_jobs "$reference" 5000 reference_paths
else
    read_completed_jobs "$campaign" 5000 job_paths
fi

run_scan() {
    local dest=$1
    shift
    srun --input=none --export=ALL --ntasks=1 --cpus-per-task=1 "$python_bin" "$scanner" \
        "$@" --cpn-n 21 --source-beta 0.60 --cooling-step 25 --topology-observables \
        --bootstrap 200 --seed 20261124 > "$dest.tmp"
    mv "$dest.tmp" "$dest"
}

module purge
module load Python SciPy-bundle matplotlib
python_bin=$(type -P python3 || type -P python)
"$python_bin" -c 'import numpy, scipy, matplotlib'
mkdir "$output"
cp "$campaign/jobs.tsv" "$output/jobs.tsv"
sha256sum "$scanner" "$repo/analyze_nested_sampling.py" "$repo/utils/nest_sampl.py" > "$output/analysis_sources.sha256"
if [[ -n $reference ]]; then
    cp "$reference/jobs.tsv" "$output/original_jobs.tsv"
    for proposals in 15500 31000; do
        path=${job_paths[$proposals]}
        old=${reference_paths[$proposals]}
        run_scan "$output/p${proposals}_original.csv" "$old"/run_{0..9} \
            --targets 0.60 0.61 --updates 5000
        run_scan "$output/p${proposals}_deep.csv" "$path"/run_{0..9} \
            --targets 0.60 0.61 --updates 500 1000 2000 5000 10000 20000
        run_scan "$output/p${proposals}_combined_5000.csv" "$old"/run_{0..9} "$path"/run_{0..9} \
            --targets 0.60 0.61 --updates 5000
    done
else
    for proposals in 15500 31000; do
        path=${job_paths[$proposals]}
        run_scan "$output/p${proposals}_depth.csv" "$path"/run_{0..9} \
            --targets 0.68 0.70 0.72 0.74 0.76 --updates 1000 2000 3500 5000
    done
fi
touch "$output/completed"
echo "N=21 L=72 target-beta scan: $output"
