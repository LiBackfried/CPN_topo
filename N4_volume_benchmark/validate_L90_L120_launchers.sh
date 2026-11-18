#!/bin/bash
# Local integration checks with mock Slurm/executables; submits no cluster jobs.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L90-L120-launchers.XXXXXXXX)
project="$work/project"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$work/scratch"
cp "$repo/N4_volume_benchmark/"{benchmark_L90_L120_ubelix.sh,run_timing_L90_L120_ubelix.sh} "$project/N4_volume_benchmark/"
cp -r "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k" "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/"
for file in "$repo/N4_volume_benchmark/"*L90_L120*.sh \
    "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/"*.conf \
    "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh"; do
    if [[ $file == *.sh ]]; then bash -n "$file"; fi
    ! LC_ALL=C grep -q $'\r' "$file"
done
module() { return 0; }
export -f module
cat > "$project/cpn_ns_N4" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
steps=$(awk '$1=="num_ns_meas" {print $2-1}' "$1")
awk -v n="$steps" 'BEGIN {for(i=1;i<=n;i++) print i,1,1,1}' > acceptance_rate.dat
awk -v n="$((steps+1))" 'BEGIN {for(i=1;i<=n;i++) print i}' > dati.dat
awk -v n="$((11*(steps+1)))" 'BEGIN {for(i=1;i<=n;i++) print i}' > topo.dat
printf 'checkpoint\n' | tee live_energy.dat rng_state.dat >/dev/null
for live in {0..49}; do printf 'checkpoint\n' > "conf.dat_live_$live"; done
SH
cat > "$project/cpn_N4" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
steps=$(awk '$1=="num_MC_step" {print $2}' "$1")
awk -v n="$((steps/10))" 'BEGIN {for(i=1;i<=n;i++) print i*10}' > dati.dat
awk -v n="$((11*steps/10))" 'BEGIN {for(i=1;i<=n;i++) print i}' > topo.dat
printf 'checkpoint\n' | tee conf.dat rng_state.dat >/dev/null
SH
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
count=$(wc -l < "$MOCK_RECORD")
id=$((9101+count))
printf '%s\t%s\n' "$id" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* && $* == *--kill-on-bad-exit=1* ]]
while [[ $1 == --* ]]; do shift; done
for ((task=0; task<SLURM_NTASKS; task++)); do SLURM_PROCID=$task "$@"; done
SH
chmod +x "$project/"{cpn_N4,cpn_ns_N4} "$work/bin/"{srun,sbatch}
export PATH="$work/bin:$PATH" NS_SCRATCH="$work/scratch" SLURM_SUBMIT_DIR="$project"
export MOCK_RECORD="$work/submissions.tsv"
touch "$MOCK_RECORD"
cd "$project"
# Default submits only L90; inherited sbatch options must not change the task count/time.
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_INIT_SWEEPS=1 bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh > "$work/default_submit.log"
[[ $(wc -l < "$MOCK_RECORD") == 6 ]]
! grep -q -- 'L120' "$MOCK_RECORD"
bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh all > "$work/all_submit.log"
[[ $(wc -l < "$MOCK_RECORD") == 18 ]]
campaign=$(awk -F ': ' '/^Timing campaign:/ {print $2}' "$work/all_submit.log")
manifest="$campaign/jobs.tsv"
[[ $(wc -l < "$manifest") == 13 ]]
[[ $(grep -c -- '--ntasks=4 --cpus-per-task=1 --time=00:45:00' "$MOCK_RECORD") == 18 ]]
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
while IFS=$'\t' read -r kind l beta stoc steps seeds job path; do
    [[ $kind == kind ]] && continue
    SLURM_JOB_ID=$job bash "$campaign/run_timing_L90_L120_ubelix.sh" "$kind" "$l" "$steps" "$stoc" "$seeds" "$campaign" > /dev/null
    [[ -f "$path/completed" ]]
    for task in 0 1 2 3; do
        config="$path/run_$task/input.conf"
        awk -v l="$l" -v b="$beta" -v s="$((seeds+task))" '
            $1=="size" {a=($2==l && $3==l)} $1=="beta" {b_ok=($2==b)}
            $1=="rng_seed" {s_ok=($2==s)} END {exit !(a && b_ok && s_ok)}' "$config"
        # Synthetic timings with a known 0.1 seconds/step slope; the jobs above used real GNU time.
        printf 'synthetic-host\nMock CPU\n' > "$path/run_$task/node.txt"
        awk -v n="$steps" 'BEGIN {printf "elapsed_seconds=%.2f\nmax_rss_kib=5120\n",10+0.1*n}' > "$path/run_$task/timing.txt"
    done
done < "$manifest"
bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh report "$manifest" > "$work/report.tsv"
[[ $(wc -l < "$work/report.tsv") == 7 && $(wc -l < "$campaign/paired_rates.tsv") == 25 ]]
awk -F '\t' 'NR>1 {if ($6!=4 || $7!=0.1 || $8!=5120) exit 1}' "$work/report.tsv"
grep -q $'mcmc\t90\t0.95\t0\tMock CPU\t4\t0.100000000\t5120\t1000000' "$work/report.tsv"
grep -q $'ns\t120\t0.7\t86400\tMock CPU\t4\t0.100000000\t5120\t370000' "$work/report.tsv"
# Changing the checkout binary after submission must not change a campaign snapshot.
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N4"
info=$("$campaign/bin/cpn_ns_N4" 2>&1 || true)
grep -Fxq 'Compiled with N = 4' <<< "$info"
if bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh 90 > "$work/wrongN.log" 2>&1; then exit 1; fi
# CPU mismatch, incomplete jobs and nonpositive timing differences must fail the report.
long_path=$(awk -F '\t' '$1=="ns" && $2==90 && $4==48600 && $5==2000 {print $8}' "$manifest")
sed -i '2s/Mock CPU/Other CPU/' "$long_path/run_0/node.txt"
if bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh report "$manifest" > "$work/mismatch.tsv" 2> "$work/mismatch.log"; then exit 1; fi
sed -i '2s/Other CPU/Mock CPU/' "$long_path/run_0/node.txt"
mv "$long_path/completed" "$long_path/completed.saved"
if bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh report "$manifest" > /dev/null 2> "$work/incomplete.log"; then exit 1; fi
mv "$long_path/completed.saved" "$long_path/completed"
sed -i 's/elapsed_seconds=210.00/elapsed_seconds=1.00/' "$long_path/run_0/timing.txt"
if bash N4_volume_benchmark/benchmark_L90_L120_ubelix.sh report "$manifest" > /dev/null 2> "$work/negative.log"; then exit 1; fi
sed -i 's/elapsed_seconds=1.00/elapsed_seconds=210.00/' "$long_path/run_0/timing.txt"
# Output reuse and incorrect worker allocations must fail.
if SLURM_JOB_ID=$(basename "$long_path" | cut -d_ -f2) bash "$campaign/run_timing_L90_L120_ubelix.sh" ns 90 2000 48600 811880 "$campaign" > "$work/reuse.log" 2>&1; then exit 1; fi
if SLURM_JOB_ID=9999 SLURM_NTASKS=3 bash "$campaign/run_timing_L90_L120_ubelix.sh" ns 90 2000 48600 811880 "$campaign" > "$work/allocation.log" 2>&1; then exit 1; fi
export SLURM_JOB_ID=9200 SLURM_NTASKS=3
bash N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh > "$work/mcmc.log"
output="$NS_SCRATCH/mcmc_90_N4_beta0p95_3x100k/job_9200"
[[ -f "$output/completed" && $(<"$output/tasks") == 3 ]]
if bash N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh > "$work/mcmc_reuse.log" 2>&1; then exit 1; fi
sed -i 's/4109002/4109001/' N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_1.conf
if SLURM_JOB_ID=9201 bash N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh > "$work/seeds.log" 2>&1; then exit 1; fi
sed -i 's/4109001/4109002/' N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_1.conf
sed -i 's/N = 4/N = 21/' "$project/cpn_N4"
if SLURM_JOB_ID=9202 bash N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_ubelix.sh > "$work/mcmc_wrongN.log" 2>&1; then exit 1; fi
echo "Passed shell/LF, mock submission, snapshot, all 12 timing jobs/configs/counts, report slopes/projections, CPU/incomplete/timing guards, output reuse, allocation, three production chains, duplicate seeds and wrong-N checks. Local artifacts: $work"
