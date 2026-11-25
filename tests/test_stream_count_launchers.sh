#!/bin/bash
# Submission/phase routing with fake Slurm and Python; never contacts UBELIX.
set -euo pipefail
trap 'printf "Failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
source_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
testroot=$(mktemp -d /tmp/cpn-stream-count.XXXXXXXX)
repo="$testroot/repo"
mkdir -p "$repo/N4_volume_benchmark" "$testroot/bin"
git -C "$source_repo" init -q "$repo"
git -C "$repo" -c user.name=Mock -c user.email=mock@example.invalid commit --allow-empty -qm 'Mock fixture'
for file in scan_stream_count.py run_L120_stream_count_ubelix.sh submit_L120_stream_count_ubelix.sh; do
    cp "$source_repo/N4_volume_benchmark/$file" "$repo/N4_volume_benchmark/"
done
for file in "$repo/N4_volume_benchmark/"*.sh "$source_repo/tests/test_stream_count_launchers.sh"; do
    bash -n "$file"; ! LC_ALL=C grep -q $'\r' "$file"
done
export NS_SCRATCH="$testroot/scratch" SLURM_SUBMIT_DIR="$repo"
for id in 22885157 22904262 22904264 23350703 23350705 23350707; do
    root="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    mkdir -p "$root"; touch "$root/completed"
    echo 120 > "$root/lattice"; echo 4 > "$root/tasks"
done
mcmc="$NS_SCRATCH/mcmc_120_N4_beta1p0_3x100k/job_22780263"
mkdir -p "$mcmc"; touch "$mcmc/completed"
echo 120 > "$mcmc/lattice"; echo 3 > "$mcmc/tasks"
cat > "$testroot/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
id=$((98001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\n' "$id" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$testroot/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $1 == --export=ALL ]]; shift
"$@"
SH
cat > "$testroot/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $1 != -c ]] || exit 0
[[ $1 != -u ]] || shift
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
while (( $# )); do
    if [[ $1 == --output ]]; then
        mkdir -p "$2"; touch "$2/completed"; exit 0
    fi
    shift
done
exit 3
SH
chmod +x "$testroot/bin/"{sbatch,srun,python}
module() { return 0; }
export -f module
export PATH="$testroot/bin:$PATH" MOCK_RECORD="$testroot/submissions.tsv" MOCK_ANALYSIS="$testroot/analysis.txt"
touch "$MOCK_RECORD" "$MOCK_ANALYSIS"
cd "$repo"
SBATCH_NTASKS=10 SBATCH_TIMELIMIT=1 bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh > "$testroot/submission.log"
campaign=$(awk -F ': ' '/^L120 stream-count campaign:/ {print $2}' "$testroot/submission.log")
[[ $(wc -l < "$MOCK_RECORD") == 3 && $(wc -l < "$campaign/jobs.tsv") == 4 ]]
grep -q -- '--dependency=afterok:98001 --array=0-8%2' "$MOCK_RECORD"
grep -q -- '--dependency=afterok:98002.*--mem-per-cpu=4G' "$MOCK_RECORD"
[[ -s "$campaign/resume_command.txt" && $(wc -l < "$campaign/raw_inputs.tsv") == 8 ]]
export SLURM_NTASKS=1 SLURM_CPUS_PER_TASK=1 SLURM_JOB_ID=98001
bash "$campaign/worker.sh" prepare "$campaign" > "$testroot/prepare.log"
[[ -f "$campaign/cache/completed" ]]
for task in {0..8}; do
    SLURM_ARRAY_TASK_ID=$task SLURM_JOB_ID=98002 bash "$campaign/worker.sh" evaluate "$campaign" > "$testroot/task_$task.log"
    [[ -f "$campaign/evaluations/task_$task/completed" ]]
done
SLURM_JOB_ID=98003 bash "$campaign/worker.sh" collect "$campaign" > "$testroot/report.log"
[[ -f "$campaign/report_98003/completed" ]]
grep -q -- '--counts 6 8 12 16 20 24 --orderings 8 --bootstrap 200 --joint-draws 1000 --seed 20261125' "$MOCK_ANALYSIS"
grep -q 'job_23350707' "$MOCK_ANALYSIS"
bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh --resume "$campaign" > "$testroot/resume.log"
[[ $(wc -l < "$MOCK_RECORD") == 5 && $(wc -l < "$campaign/jobs.tsv") == 6 ]]
tail -n 2 "$MOCK_RECORD" | grep -q -- '--array=0-8%2'
tail -n 1 "$MOCK_RECORD" | grep -q -- '--dependency=afterok:98004'
if SLURM_NTASKS=2 bash "$campaign/worker.sh" collect "$campaign" > /dev/null 2>&1; then exit 1; fi
if bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh --resume "$testroot" > /dev/null 2>&1; then exit 1; fi
rm -- "$root/completed"
if bash N4_volume_benchmark/submit_L120_stream_count_ubelix.sh > /dev/null 2>&1; then exit 1; fi
[[ $(wc -l < "$MOCK_RECORD") == 5 ]]
echo "Passed source cache, nine-task array/concurrency, collector dependencies, raw IDs, phase routing, resume and rejection checks. Local artifacts: $testroot"
