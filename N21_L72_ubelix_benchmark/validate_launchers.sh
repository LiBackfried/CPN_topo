#!/bin/bash
# Integration checks using mocked Slurm and simulation output; no remote jobs.
set -euo pipefail
export LC_ALL=C
setup=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd "$setup/.." && pwd -P)
for file in "$setup/"*.sh "$setup/input.template"; do
    [[ $file != *.sh ]] || bash -n "$file"
    ! grep -q $'\r' "$file"
done
work=$(mktemp -d /tmp/cpn-N21-launcher-tests.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
project="$work/project"
mkdir -p "$project/N21_L72_ubelix_benchmark" "$project/utils" "$work/bin" "$work/scratch"
cp "$setup/"{submit_ubelix.sh,run_ubelix.sh,analyze_ubelix.sh,summarize.py,input.template} "$project/N21_L72_ubelix_benchmark/"
cp "$repo/analyze_nested_sampling.py" "$project/"
cp "$repo/utils/"*.py "$project/utils/"
module() { return 0; }
export -f module
export REAL_PYTHON
REAL_PYTHON=$(command -v python3)
cat > "$project/cpn_ns_N21" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 21'; exit 1; fi
steps=$(awk '$1=="num_ns_meas" {print $2-1}' "$1")
awk -v n="$steps" 'BEGIN {for(i=1;i<=n;i++) print i,0.9,0.99,0.8}' > acceptance_rate.dat
awk -v n="$steps" 'BEGIN {for(i=0;i<=n;i++) printf "0 %.16f 12 8\n",0.9-i*0.00001}' > dati.dat
awk -v n="$steps" 'BEGIN {for(i=0;i<=n;i++) for(c=0;c<=50;c+=5) print 0,c,1,1,1}' > topo.dat
awk -v n="$steps" 'BEGIN {for(i=0;i<50;i++) printf "%.16f\n",0.9-n*0.00001-i*0.0000001}' > live_energy.dat
printf 'synthetic RNG\n' > rng_state.dat
printf 'synthetic log\n' > log.dat
for i in {0..49}; do printf '2 21 72 72 MOCK_HASH\n' > "conf.dat_live_$i"; done
awk -v n="$steps" 'BEGIN {printf "#NS loop wall time: %.9f s\n#Simulation time: %.9f s\n#Heatbath init. time: 0.5 s\n",0.1*n,0.09*n}'
sleep 0.02
SH
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ ${MOCK_FAIL_SECOND:-0} == 1 && $* == *N21_L72_p31000* ]]; then exit 1; fi
id=$((920001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\n' "$id" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* ]]
if (( SLURM_NTASKS == 10 )); then
    [[ $* == *--cpu-bind=cores* && $* == *--kill-on-bad-exit=1* ]]
fi
while [[ $1 == --* ]]; do shift; done
for ((task=0; task<SLURM_NTASKS; task++)); do SLURM_PROCID=$task "$@"; done
SH
cat > "$work/bin/python3" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
if [[ $1 == -c ]]; then exit 0; fi
if [[ $1 == */analyze_nested_sampling.py ]]; then
    while (( $# )); do
        if [[ $1 == --output ]]; then out=$2; break; fi
        shift
    done
    mkdir -p "$out"
    cp "$MOCK_RESULT" "$out/results.json"
else
    exec "$REAL_PYTHON" "$@"
fi
SH
chmod +x "$project/cpn_ns_N21" "$work/bin/"*
export PATH="$work/bin:$PATH" NS_SCRATCH="$work/scratch" MOCK_RECORD="$work/submissions.tsv"
export MOCK_RESULT="$work/mock_results.json" MOCK_ANALYSIS="$work/analysis_calls.txt"
touch "$MOCK_RECORD"
"$REAL_PYTHON" -c 'import json,sys; keys=("mean_action_density","mean_G0","mean_Gk","xi_L_squared","mean_Q_U","mean_Q_U_squared","chi_topological"); json.dump({"settings":{"cpn_n":21,"source_beta":0.6,"beta_reweighted":False},"estimates":dict.fromkeys(keys,1.),"bootstrap_standard_errors":dict.fromkeys(keys,.1)},open(sys.argv[1],"w"))' "$MOCK_RESULT"
cd "$project"
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 bash N21_L72_ubelix_benchmark/submit_ubelix.sh 3 > "$work/submission.log"
[[ $(wc -l < "$MOCK_RECORD") == 3 ]]
campaign=$(sed -n 's/^Campaign: //p' "$work/submission.log")
[[ $(wc -l < "$campaign/jobs.tsv") == 3 ]]
grep -q -- '--dependency=afterok:920001:920002' "$MOCK_RECORD"
[[ $(grep -c -- '--ntasks=10 --cpus-per-task=1 --mem-per-cpu=2G --time=02:00:00' "$MOCK_RECORD") == 2 ]]
grep -q -- '--ntasks=1 --cpus-per-task=1 --mem-per-cpu=8G' "$MOCK_RECORD"
export SLURM_NTASKS=10 SLURM_CPUS_PER_TASK=1
while IFS=$'\t' read -r proposals steps seeds job path; do
    [[ $proposals == proposals ]] && continue
    SLURM_JOB_ID=$job bash "$campaign/snapshot/run_ubelix.sh" "$proposals" "$steps" "$seeds" "$campaign" > /dev/null
    [[ -f $path/completed ]]
done < "$campaign/jobs.tsv"
[[ $(awk '$1=="rng_seed" {print $2}' "$campaign"/job_*/run_*/input.conf | sort -u | wc -l) == 20 ]]
# Test real reporting plus mocked canonical-analysis routing and fixed N.
SLURM_JOB_ID=920003 SLURM_NTASKS=1 bash "$campaign/snapshot/analyze_ubelix.sh" "$campaign" > "$work/analysis.log"
output="$campaign/analysis_920003"
[[ -f $output/completed && $(wc -l < "$output/timings.csv") == 21 ]]
[[ $(wc -l < "$output/observable_comparison.csv") == 8 ]]
[[ $(grep -c -- '--cpn-n 21 --bootstrap 500 --seed 20261124' "$MOCK_ANALYSIS") == 2 ]]
# Wrong model, allocation, output reuse, missing completion, and seed corruption fail.
sed -i 's/N = 21/N = 4/' "$project/cpn_ns_N21"
if bash N21_L72_ubelix_benchmark/submit_ubelix.sh 3 > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N21"
if SLURM_JOB_ID=999991 SLURM_NTASKS=1 bash "$campaign/snapshot/run_ubelix.sh" 15500 3 21720001 "$campaign" > "$work/allocation.log" 2>&1; then exit 1; fi
if SLURM_JOB_ID=920001 bash "$campaign/snapshot/run_ubelix.sh" 15500 3 21720001 "$campaign" > "$work/reuse.log" 2>&1; then exit 1; fi
mv "$campaign/job_920001/completed" "$campaign/job_920001/completed.saved"
if "$REAL_PYTHON" "$setup/summarize.py" "$campaign" "$work/report" > "$work/incomplete.log" 2>&1; then exit 1; fi
mv "$campaign/job_920001/completed.saved" "$campaign/job_920001/completed"
sed -i 's/rng_seed 21720002/rng_seed 21720001/' "$campaign/job_920001/run_1/input.conf"
if "$REAL_PYTHON" "$setup/summarize.py" "$campaign" "$work/report" > "$work/seeds.log" 2>&1; then exit 1; fi
sed -i 's/rng_seed 21720001/rng_seed 21720002/' "$campaign/job_920001/run_1/input.conf"
# Immutable snapshots survive a changed checkout binary; workers reject a changed snapshot.
sed -i 's/N = 21/N = 4/' "$project/cpn_ns_N21"
info=$("$campaign/snapshot/cpn_ns_N21" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info"
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N21"
printf '\n# tampered\n' >> "$campaign/snapshot/cpn_ns_N21"
if SLURM_JOB_ID=999992 bash "$campaign/snapshot/run_ubelix.sh" 15500 3 21720001 "$campaign" > "$work/hash.log" 2>&1; then exit 1; fi
# Partial submission keeps a manifest of the successful first job and submits no analysis.
count=$(wc -l < "$MOCK_RECORD")
if MOCK_FAIL_SECOND=1 bash N21_L72_ubelix_benchmark/submit_ubelix.sh 3 > "$work/partial.log" 2>&1; then exit 1; fi
[[ $(wc -l < "$MOCK_RECORD") == "$((count+1))" ]]
partial=$(sed -n 's/^Campaign: //p' "$work/partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 2 && ! -e $partial/analysis_job_id.txt ]]
# Default depth is exactly 5000 updates, even when caller NS_* settings differ.
NS_STOC=1 NS_INIT_SWEEPS=1 bash N21_L72_ubelix_benchmark/submit_ubelix.sh > "$work/default.log"
default=$(sed -n 's/^Campaign: //p' "$work/default.log")
awk -F '\t' 'NR>1 {if ($2!=5000) exit 1}' "$default/jobs.tsv"
echo 'PASS: syntax/LF, resources, configs, twenty seeds, workers, reports, analysis routing and failure guards (mock Slurm).'
