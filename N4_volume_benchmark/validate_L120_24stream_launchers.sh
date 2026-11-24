#!/bin/bash
# Mocked integration checks; no cluster access or production simulations.
set -euo pipefail
trap 'printf "Validation failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L120-24streams.XXXXXXXX)
project="$work/project" scratch="$work/scratch"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$scratch"
git -C "$repo" init -q "$project"
git -C "$project" -c user.name=Mock -c user.email=mock@example.invalid commit --allow-empty -qm 'Mock analysis fixture'
cp "$repo/N4_volume_benchmark/"{add_L120_12_to24_300k_ubelix.sh,analyze_L120_24x300k_ubelix.sh,run_ubelix.sh} "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/run_0"
for file in "$repo/N4_volume_benchmark/"{add_L120_12_to24_300k_ubelix.sh,analyze_L120_24x300k_ubelix.sh,validate_L120_24stream_launchers.sh}; do
    bash -n "$file"
    ! LC_ALL=C grep -q $'\r' "$file"
done
module() { return 0; }
export -f module
mkdir -p "$project/utils"
for file in scan_depth.py compare_action_bins.py; do touch "$project/N4_volume_benchmark/$file"; done
touch "$project/analyze_nested_sampling.py"
for file in nest_sampl.py mcmc.py cpn_io.py plot_mcmc.py; do touch "$project/utils/$file"; done
cat > "$project/cpn_ns_N4" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
for file in dati.dat topo.dat acceptance_rate.dat live_energy.dat rng_state.dat; do echo 'mock output' > "$file"; done
echo 'Theory: 2d CP^{N-1} model with N = 4' > log.dat
for live in {0..49}; do echo 'mock live configuration' > "conf.dat_live_$live"; done
SH
chmod +x "$project/cpn_ns_N4"
# Use the actual three old history shapes (120k+120k+60k and two 150k+150k).
for spec in '22780262 120001 1 0 - 828968384' '22860149 120001 2 1 22780262 828968384' \
            '22885157 60001 2 1 22860149 828968384' '22904261 150001 1 0 - 335358449' \
            '22904262 150001 2 1 22904261 335358449' '22904263 150001 1 0 - 691294503' \
            '22904264 150001 2 1 22904263 691294503'; do
    read -r id points start rng ancestor base <<< "$spec"
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    mkdir -p "$root"; touch "$root/completed"
    echo 120 > "$root/lattice"; echo 4 > "$root/tasks"
    cp "$project/cpn_ns_N4" "$root/cpn_ns_N4"
    for run in 0 1 2 3; do
        out="$root/run_$run"; mkdir "$out"
        awk -v n="$points" -v start="$start" -v rng="$rng" -v seed="$((base+run))" '
            /^#/ {next}
            $1=="size" {print $1,120,120; next}
            $1=="num_single_site_stoc_upd" {print $1,86400; next}
            $1=="num_ns_meas" {print $1,n; next}
            $1=="start" {print $1,start; next}
            $1=="rng_start" {print $1,rng; next}
            $1=="rng_seed" {print $1,seed; next}
            {print}
        ' "$project/$template/run_0" > "$out/input.conf"
        for file in dati.dat topo.dat acceptance_rate.dat; do echo saved > "$out/$file"; done
        echo 'Theory: 2d CP^{N-1} model with N = 4' > "$out/log.dat"
        if [[ $ancestor != - ]]; then printf '../../job_%s/run_%s\n' "$ancestor" "$run" > "$out/parent_run"; fi
    done
done
existing="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22885157"
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
mkdir -p "$mcmc"; touch "$mcmc/completed"
echo 120 > "$mcmc/lattice"; echo 3 > "$mcmc/tasks"
for run in 0 1 2; do
    mkdir "$mcmc/run_$run"
    cp "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_$run.conf" "$mcmc/run_$run/input.conf"
    for file in dati.dat topo.dat; do echo saved > "$mcmc/run_$run/$file"; done
    echo 'Theory: 2d CP^{N-1} model with N = 4' > "$mcmc/run_$run/log.dat"
done
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
id=$((96001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${NS_STOC:-}" "${NS_EXECUTABLE:-}" \
    "${NS_INIT_SWEEPS:-}" "${NS_INIT_SPACING:-}" "${NS_SEED_BASE:-}" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* ]]
while [[ $1 == --* ]]; do shift; done
for ((task=0; task<SLURM_NTASKS; task++)); do SLURM_PROCID=$task "$@"; done
SH
cat > "$work/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
if [[ $1 == N4_volume_benchmark/scan_depth.py ]]; then echo synthetic_csv_header; fi
SH
# Exercise collisions with every old group and with another fresh batch.
cat > "$work/bin/od" <<'SH'
#!/bin/bash
n=$(cat "$MOCK_RANDOM_COUNT")
echo "$((n+1))" > "$MOCK_RANDOM_COUNT"
words=(828968383 335358448 691294502 100000000 100000000 200000000 300000000)
if (( n < 7 )); then echo "${words[$n]}"; else echo "$((400000000+n*100))"; fi
SH
chmod +x "$work/bin/"{sbatch,srun,python,od}
export PATH="$work/bin:$PATH" NS_SCRATCH="$scratch" SLURM_SUBMIT_DIR="$project"
export MOCK_RECORD="$work/submissions.tsv" MOCK_ANALYSIS="$work/analysis.txt" MOCK_RANDOM_COUNT="$work/random_count"
touch "$MOCK_RECORD" "$MOCK_ANALYSIS"; echo 0 > "$MOCK_RANDOM_COUNT"
cd "$project"
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N4"
old_hash=$(sha256sum "$existing/run_0/dati.dat")
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_INIT_SWEEPS=1 NS_INIT_SPACING=1 \
    NS_EXECUTABLE=/missing NS_SEED_BASE=1 bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/submit.log"
campaign=$(awk -F ': ' '/^L120 24-stream campaign records:/ {print $2}' "$work/submit.log")
[[ $(wc -l < "$MOCK_RECORD") == 7 && $(wc -l < "$campaign/jobs.tsv") == 8 ]]
[[ $(wc -l < "$campaign/planned_seeds.tsv") == 25 && $(<"$campaign/analysis_job_id.txt") == 96007 ]]
awk -F '\t' 'NR>1 {if ($3<=0 || $3>=2147483399 || seen[$3]++) exit 1; n++} END {if(n!=24) exit 1}' "$campaign/planned_seeds.tsv"
[[ $(<"$MOCK_RANDOM_COUNT") == 7 && $(wc -l < "$campaign/existing_inputs.tsv") == 5 ]]
grep -q -- '--dependency=afterok:96002:96004:96006.*analyze_L120_24x300k_ubelix.sh 22885157 22904262 22904264 96002 96004 96006 22780263' "$MOCK_RECORD"
awk -F '\t' 'NR==2 || NR==4 || NR==6 {if ($2!="" || $3!="" || $4!="" || $5!="" || $6!="") exit 1}' "$MOCK_RECORD"
[[ -s "$campaign/analyze_command.txt" && -s "$campaign/source_sha256.txt" ]]
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
for batch in 1 2 3; do
    start_id=$((96001+2*(batch-1))) leaf_id=$((96002+2*(batch-1)))
    base=$(awk -F '\t' -v role="fresh${batch}_start" '$1==role {print $6}' "$campaign/jobs.tsv")
    NS_STOC=86400 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_EXECUTABLE="$existing/cpn_ns_N4" \
        NS_SEED_BASE="$base" SLURM_JOB_ID=$start_id bash N4_volume_benchmark/run_ubelix.sh 120 150000 > "$work/start$batch.log"
    start_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$start_id"
    before=$(sha256sum "$start_root/run_0/rng_state.dat")
    env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_EXECUTABLE -u NS_SEED_BASE \
        SLURM_JOB_ID=$leaf_id bash N4_volume_benchmark/run_ubelix.sh 120 150000 "$start_root" > "$work/leaf$batch.log"
    leaf_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$leaf_id"
    [[ -f "$leaf_root/completed" && $(sha256sum "$start_root/run_0/rng_state.dat") == "$before" ]]
    for run in 0 1 2 3; do
        for root in "$start_root" "$leaf_root"; do
            if [[ $root == "$start_root" ]]; then start=1 rng=0; else start=2 rng=1; fi
            awk -v seed="$((base+run))" -v start="$start" -v rng="$rng" '
                $1=="size" {a=($2==120 && $3==120)} $1=="beta" {b=($2==0.7)}
                $1=="num_ns_meas" {c=($2==150001)} $1=="num_single_site_stoc_upd" {d=($2==86400)}
                $1=="start" {e=($2==start)} $1=="rng_start" {f=($2==rng)} $1=="rng_seed" {g=($2==seed)}
                END {exit !(a&&b&&c&&d&&e&&f&&g)}' "$root/run_$run/input.conf"
        done
        [[ $(realpath "$leaf_root/run_$run/$(cat "$leaf_root/run_$run/parent_run")") == "$start_root/run_$run" ]]
    done
done
[[ $(sha256sum "$existing/run_0/dati.dat") == "$old_hash" ]]
export SLURM_NTASKS=1 SLURM_JOB_ID=96007
bash N4_volume_benchmark/analyze_L120_24x300k_ubelix.sh 22885157 22904262 22904264 96002 96004 96006 22780263 > "$work/analysis.log"
output="$project/N4_L120_res/combined24x300_analysis_96007"
[[ -f "$output/completed" && $(wc -l < "$output/inputs.tsv") == 8 ]]
grep -q -- '--updates 180000 210000 240000 270000 300000 --targets 0.9 0.95 1.0' "$MOCK_ANALYSIS"
grep -q -- '--updates 300000 --beta 1.0 --bins 32.*--block-size 512' "$MOCK_ANALYSIS"
[[ $(grep -c 'utils/plot_mcmc.py' "$MOCK_ANALYSIS") == 2 ]]
if bash N4_volume_benchmark/analyze_L120_24x300k_ubelix.sh 22885157 22904262 22904264 96002 96004 96004 22780263 > "$work/duplicate.log" 2>&1; then exit 1; fi
cfg="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22904264/run_0/input.conf"
cp "$cfg" "$work/config.saved"
sed -i 's/rng_seed 691294503/rng_seed 828968384/' "$cfg"
if bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/collision.log" 2>&1; then exit 1; fi
cp "$work/config.saved" "$cfg"
sed -i 's/num_ns_meas 150001/num_ns_meas 150000/' "$cfg"
if bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/depth_driver.log" 2>&1; then exit 1; fi
if SLURM_JOB_ID=96008 bash N4_volume_benchmark/analyze_L120_24x300k_ubelix.sh 22885157 22904262 22904264 96002 96004 96006 22780263 > "$work/depth_analysis.log" 2>&1; then exit 1; fi
cp "$work/config.saved" "$cfg"
mv "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22904263/run_2/topo.dat" "$work/topo.saved"
if bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/ancestor.log" 2>&1; then exit 1; fi
mv "$work/topo.saved" "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22904263/run_2/topo.dat"
sed -i 's/N = 4/N = 21/' "$existing/cpn_ns_N4"
if bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$existing/cpn_ns_N4"
[[ $(wc -l < "$MOCK_RECORD") == 7 ]]
# A failed third start records the first four submissions without silently resubmitting.
if MOCK_FAIL_MATCH=ns_L120_add12_3_start bash N4_volume_benchmark/add_L120_12_to24_300k_ubelix.sh > "$work/partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L120 24-stream campaign records:/ {print $2}' "$work/partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 5 && $(wc -l < "$MOCK_RECORD") == 11 ]]
echo "Passed 24-stream seed allocation/collisions, all old histories, six simulation jobs, 150k+150k configs/RNG/parent links, analysis/dependencies, immutability and failure guards. Local artifacts: $work"
