#!/bin/bash
# Local integration check with mock Slurm; never submits remote jobs.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L66-launchers.XXXXXXXX)
project="$work/project"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$work/scratch"
git -C "$repo" init -q "$project"
cp "$repo/N4_volume_benchmark/"{run_ubelix.sh,fresh_L66_12_ubelix.sh,analyze_L66_ubelix.sh} "$project/N4_volume_benchmark/"
cp -r "$repo/N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k" "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/"
for file in "$repo/N4_volume_benchmark/"*L66*.sh "$repo/N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh"; do
    bash -n "$file"
    ! LC_ALL=C grep -q $'\r' "$file"
done
module() { return 0; }
export -f module
cat > "$project/cpn_ns_N4" <<'SH'
#!/bin/bash
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
exit 0
SH
cat > "$project/cpn_N4" <<'SH'
#!/bin/bash
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
awk 'BEGIN {for(i=1;i<=100000;i++) print i*10}' > dati.dat
awk 'BEGIN {for(i=1;i<=1100000;i++) print i}' > topo.dat
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* ]]
while [[ $1 == --* ]]; do shift; done
for ((i=0;i<SLURM_NTASKS;i++)); do SLURM_PROCID=$i "$@"; done
SH
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
count=$(wc -l < "$MOCK_RECORD")
id=$((9001+count))
printf '%s\t%s\t%s\t%s\n' "$id" "$NS_STOC" "$NS_EXECUTABLE" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
chmod +x "$project/"{cpn_N4,cpn_ns_N4} "$work/bin/"{srun,sbatch}
export PATH="$work/bin:$PATH" NS_SCRATCH="$work/scratch" SLURM_SUBMIT_DIR="$project"
export MOCK_RECORD="$work/submissions.tsv"
touch "$MOCK_RECORD"
cd "$project"
bash N4_volume_benchmark/fresh_L66_12_ubelix.sh
[[ $(wc -l < "$MOCK_RECORD") == 4 ]]
[[ $(grep -c -- '--ntasks=4.*--time=04:00:00.*66 110000' "$MOCK_RECORD") == 3 ]]
grep -q -- '--dependency=afterok:9001:9002:9003' "$MOCK_RECORD"
campaign=$(find "$project/N4_L66_res" -mindepth 1 -maxdepth 1 -type d)
[[ $(wc -l < "$campaign/ns_jobs.tsv") == 4 && $(cat "$campaign/analysis_job_id.txt") == 9004 ]]
export SLURM_JOB_ID=9001 SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1 NS_STOC=26136
bash N4_volume_benchmark/run_ubelix.sh 66 110000
output="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L66/job_9001"
[[ -f "$output/completed" ]]
for run in 0 1 2 3; do
    awk '$1=="size" {a=($2==66 && $3==66)} $1=="beta" {b=($2==0.7)}
         $1=="num_ns_meas" {c=($2==110001)} $1=="num_single_site_stoc_upd" {d=($2==26136)}
         $1=="start" {e=($2==1)} $1=="rng_start" {f=($2==0)}
         END {exit !(a&&b&&c&&d&&e&&f)}' "$output/run_$run/input.conf"
done
[[ $(awk '$1=="rng_seed" {print $2}' "$output"/run_*/input.conf | sort -u | wc -l) == 4 ]]
if bash N4_volume_benchmark/run_ubelix.sh 66 110000 > "$work/reuse.log" 2>&1; then
    echo 'Output reuse should have failed' >&2; exit 1
fi
export SLURM_JOB_ID=9010 SLURM_NTASKS=3
bash N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh
[[ -f "$NS_SCRATCH/mcmc_66_N4_beta0p9_3x100k/job_9010/completed" ]]
# Failure paths: wrong N and duplicate seeds must stop before launching.
sed -i 's/N = 4/N = 21/' "$project/cpn_N4"
export SLURM_JOB_ID=9011
if bash N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$project/cpn_N4"
sed -i 's/4106602/4106601/' N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_1.conf
if bash N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_ubelix.sh > "$work/seeds.log" 2>&1; then exit 1; fi
# Exercise analysis argument routing and repository output containment.
for id in 9002 9003; do
    root="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L66/job_$id"
    mkdir "$root"
    printf '66\n' > "$root/lattice"
    printf '4\n' > "$root/tasks"
    touch "$root/completed"
done
cat > "$work/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
if [[ $1 == N4_volume_benchmark/scan_depth.py ]]; then echo 'synthetic_csv_header'; fi
SH
chmod +x "$work/bin/python"
export SLURM_NTASKS=1 MOCK_ANALYSIS="$work/analysis_calls.txt"
bash N4_volume_benchmark/analyze_L66_ubelix.sh 9001 9002 9003 "$project/N4_L66_res/check" 9010
[[ -f "$project/N4_L66_res/check/completed" ]]
grep -q -- '--targets 0.7 0.75 0.8 0.85 0.9 0.95 1.0 --bootstrap 200' "$MOCK_ANALYSIS"
grep -q -- '--updates 110000 --beta 0.9 --bins 32' "$MOCK_ANALYSIS"
if bash N4_volume_benchmark/analyze_L66_ubelix.sh 9001 9002 9003 "$work/outside" > "$work/output_guard.log" 2>&1; then exit 1; fi
echo "Passed shell/LF checks, mock submission/dependencies, generated NS settings/seeds, MCMC rows, output reuse, failure guards, analysis argument routing and output containment. Artifacts: $work"
