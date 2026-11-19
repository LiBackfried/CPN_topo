#!/bin/bash
# Local integration checks with mock Slurm/executables; submits no cluster jobs.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L90-L120-launchers.XXXXXXXX)
project="$work/project"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$work/scratch"
git -C "$repo" init -q "$project"
cp "$repo/N4_volume_benchmark/"{benchmark_L90_L120_ubelix.sh,run_timing_L90_L120_ubelix.sh} "$project/N4_volume_benchmark/"
cp "$repo/N4_volume_benchmark/analyze_L90_ubelix.sh" "$project/N4_volume_benchmark/"
cp "$repo/N4_volume_benchmark/"{run_ubelix.sh,analyze_L120_ubelix.sh,fresh_L120_screen_ubelix.sh} "$project/N4_volume_benchmark/"
cp -r "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k" "$project/N4_volume_benchmark/"
cp -r "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k" "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/"
for file in "$repo/N4_volume_benchmark/"*L90_L120*.sh \
    "$repo/N4_volume_benchmark/analyze_L90_ubelix.sh" \
    "$repo/N4_volume_benchmark/analyze_L120_ubelix.sh" \
    "$repo/N4_volume_benchmark/fresh_L120_screen_ubelix.sh" \
    "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/"*.conf \
    "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh" \
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
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
count=$(wc -l < "$MOCK_RECORD")
id=$((9101+count))
printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$*" "${NS_STOC:-}" "${NS_INIT_SWEEPS:-}" "${NS_INIT_SPACING:-}" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* ]]
if (( SLURM_NTASKS > 1 )); then [[ $* == *--kill-on-bad-exit=1* ]]; fi
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
# Analysis routing and guards. Python is mocked; no physics/bootstrap results are generated.
ns="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L90/job_22635195"
mkdir -p "$(dirname "$ns")"
cp -r "$long_path" "$ns"
for run in 0 1 2 3; do sed -i 's/num_ns_meas 2001/num_ns_meas 80001/' "$ns/run_$run/input.conf"; done
cat > "$work/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
if [[ $1 == N4_volume_benchmark/scan_depth.py ]]; then printf 'synthetic_csv_header\n'; fi
SH
chmod +x "$work/bin/python"
export MOCK_ANALYSIS="$work/analysis_calls.txt" SLURM_JOB_ID=9300 SLURM_NTASKS=1
bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 > "$work/analysis.log"
analysis="$project/N4_L90_res/screen_ns22635195_mc9200_analysis_9300"
[[ -f "$analysis/completed" && -s "$analysis/depth.csv" ]]
grep -q -- '--updates 20000 40000 60000 --targets 0.9 0.95 1.0 --bootstrap 200' "$MOCK_ANALYSIS"
grep -q -- '--burn-in 20000 --output' "$MOCK_ANALYSIS"
[[ $(grep -c 'utils/plot_mcmc.py' "$MOCK_ANALYSIS") == 2 ]]
# Custom prefixes are passed unchanged; the real scanner adds the deepest prefix.
SLURM_JOB_ID=9301 bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 40000 80000 100000 120000 > "$work/custom_prefixes.log"
grep -q -- '--updates 40000 80000 100000 120000 --targets' "$MOCK_ANALYSIS"
if bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 > "$work/analysis_reuse.log" 2>&1; then exit 1; fi
if SLURM_JOB_ID=9302 bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 invalid > "$work/prefix_guard.log" 2>&1; then exit 1; fi
mv "$ns/completed" "$ns/completed.saved"
if SLURM_JOB_ID=9302 bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 > "$work/analysis_incomplete.log" 2>&1; then exit 1; fi
mv "$ns/completed.saved" "$ns/completed"
sed -i 's/num_single_site_stoc_upd 48600/num_single_site_stoc_upd 24300/' "$ns/run_0/input.conf"
if SLURM_JOB_ID=9302 bash N4_volume_benchmark/analyze_L90_ubelix.sh 22635195 9200 > "$work/analysis_settings.log" 2>&1; then exit 1; fi
# The L120 campaign has its own simulations/dependencies, so it can proceed alongside L90.
sed -i 's/N = 21/N = 4/' "$project/cpn_ns_N4" "$project/cpn_N4"
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_SEED_BASE=1 \
    bash N4_volume_benchmark/fresh_L120_screen_ubelix.sh > "$work/L120_submit.log"
[[ $(wc -l < "$MOCK_RECORD") == 21 ]]
l120_campaign=$(awk -F ': ' '/^L120 campaign records:/ {print $2}' "$work/L120_submit.log")
[[ $(wc -l < "$l120_campaign/jobs.tsv") == 4 && -s "$l120_campaign/analyze_command.txt" ]]
l120_ns_id=$(awk -F '\t' '$1=="ns" {print $2}' "$l120_campaign/jobs.tsv")
l120_mc_id=$(awk -F '\t' '$1=="mcmc" {print $2}' "$l120_campaign/jobs.tsv")
l120_analysis_id=$(cat "$l120_campaign/analysis_job_id.txt")
grep -q -- "--dependency=afterok:$l120_ns_id:$l120_mc_id" "$MOCK_RECORD"
grep -q -- '--ntasks=4 --cpus-per-task=1 --time=12:00:00.*120 120000' "$MOCK_RECORD"
grep -q -- '--ntasks=3 --cpus-per-task=1 --time=16:00:00' "$MOCK_RECORD"
awk -F '\t' -v id="$l120_ns_id" '$1==id {ok=($3==86400 && $4==20 && $5==8)} END {exit !ok}' "$MOCK_RECORD"
SLURM_JOB_ID=$l120_ns_id SLURM_NTASKS=4 NS_STOC=86400 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 \
    bash N4_volume_benchmark/run_ubelix.sh 120 120000 > "$work/L120_ns.log"
l120_ns="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L120/job_$l120_ns_id"
[[ -f "$l120_ns/completed" ]]
for run in 0 1 2 3; do
    awk '$1=="size" {a=($2==120 && $3==120)} $1=="num_ns_meas" {b=($2==120001)}
         $1=="num_single_site_stoc_upd" {c=($2==86400)} $1=="beta" {d=($2==0.7)}
         $1=="start" {e=($2==1)} $1=="rng_start" {f=($2==0)} END {exit !(a&&b&&c&&d&&e&&f)}' "$l120_ns/run_$run/input.conf"
done
[[ $(awk '$1=="rng_seed" {print $2}' "$l120_ns"/run_*/input.conf | sort -u | wc -l) == 4 ]]
SLURM_JOB_ID=$l120_mc_id SLURM_NTASKS=3 bash N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh > "$work/L120_mcmc.log"
l120_mc="$NS_SCRATCH/mcmc_120_N4_beta1p0_3x100k/job_$l120_mc_id"
[[ -f "$l120_mc/completed" && $(<"$l120_mc/tasks") == 3 ]]
if SLURM_JOB_ID=$l120_mc_id SLURM_NTASKS=3 bash N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh > "$work/L120_reuse.log" 2>&1; then exit 1; fi
SLURM_JOB_ID=$l120_analysis_id bash N4_volume_benchmark/analyze_L120_ubelix.sh "$l120_ns_id" "$l120_mc_id" > "$work/L120_analysis.log"
l120_analysis="$project/N4_L120_res/screen_ns${l120_ns_id}_mc${l120_mc_id}_analysis_${l120_analysis_id}"
[[ -f "$l120_analysis/completed" && -s "$l120_analysis/depth.csv" ]]
grep -q -- '--updates 30000 60000 90000 --targets 0.9 0.95 1.0 --bootstrap 200' "$MOCK_ANALYSIS"
grep -q -- "scan_depth.py $l120_ns" "$MOCK_ANALYSIS"
grep -q -- "plot_mcmc.py $l120_mc --burn-in 20000" "$MOCK_ANALYSIS"
sed -i 's/num_single_site_stoc_upd 86400/num_single_site_stoc_upd 43200/' "$l120_ns/run_0/input.conf"
if SLURM_JOB_ID=9400 bash N4_volume_benchmark/analyze_L120_ubelix.sh "$l120_ns_id" "$l120_mc_id" > "$work/L120_settings.log" 2>&1; then exit 1; fi
sed -i 's/num_single_site_stoc_upd 43200/num_single_site_stoc_upd 86400/' "$l120_ns/run_0/input.conf"
sed -i 's/beta 1.0/beta 0.95/' "$l120_mc/run_0/input.conf"
if SLURM_JOB_ID=9400 bash N4_volume_benchmark/analyze_L120_ubelix.sh "$l120_ns_id" "$l120_mc_id" > "$work/L120_beta.log" 2>&1; then exit 1; fi
sed -i 's/4112002/4112001/' N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_1.conf
if SLURM_JOB_ID=9400 SLURM_NTASKS=3 bash N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh > "$work/L120_seeds.log" 2>&1; then exit 1; fi
sed -i 's/4112001/4112002/' N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_1.conf
sed -i 's/N = 4/N = 21/' "$project/cpn_N4"
if SLURM_JOB_ID=9401 SLURM_NTASKS=3 bash N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh > "$work/L120_wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$project/cpn_N4"
# A partial submission leaves its successful NS job in the new manifest.
if MOCK_FAIL_MATCH=mcmc_120_N4 bash N4_volume_benchmark/fresh_L120_screen_ubelix.sh > "$work/L120_partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L120 campaign records:/ {print $2}' "$work/L120_partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 2 && $(wc -l < "$MOCK_RECORD") == 22 ]]
echo "Passed shell/LF, both-volume timing jobs/reports, snapshots, production counts/seeds/N guards, L90/L120 analysis routing/settings, L120 submission resources/dependencies, generated 120k NS configs/seeds, and partial-submission records. Local artifacts: $work"
