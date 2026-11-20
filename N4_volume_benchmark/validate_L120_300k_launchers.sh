#!/bin/bash
# Local Slurm/Python/simulation mocks; no cluster submissions or physics results.
set -euo pipefail
trap 'printf "Validation failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L120-300k-launchers.XXXXXXXX)
project="$work/project" scratch="$work/scratch"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$scratch"
git -C "$repo" init -q "$project"
cp "$repo/N4_volume_benchmark/"{add_L120_8x300k_ubelix.sh,analyze_L120_12x300k_ubelix.sh,run_ubelix.sh} "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/run_0"
for file in "$repo/N4_volume_benchmark/"{add_L120_8x300k_ubelix.sh,analyze_L120_12x300k_ubelix.sh,validate_L120_300k_launchers.sh,run_ubelix.sh}; do
    bash -n "$file"
    if LC_ALL=C grep -q $'\r' "$file"; then echo "CRLF in $file" >&2; exit 1; fi
done
module() { return 0; }
export -f module
cat > "$project/cpn_ns_N4" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
for file in dati.dat topo.dat acceptance_rate.dat live_energy.dat rng_state.dat; do printf 'mock output\n' > "$file"; done
printf 'Theory: 2d CP^{N-1} model with N = 4\n' > log.dat
for live in {0..49}; do printf 'mock live configuration\n' > "conf.dat_live_$live"; done
SH
chmod +x "$project/cpn_ns_N4"
for spec in '22780262 120001 1 0 -' '22860149 120001 2 1 22780262' '22885157 60001 2 1 22860149'; do
    read -r id points start rng ancestor <<< "$spec"
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    mkdir -p "$root"
    touch "$root/completed"
    printf '120\n' > "$root/lattice"; printf '4\n' > "$root/tasks"
    cp "$project/cpn_ns_N4" "$root/cpn_ns_N4"
    for run in 0 1 2 3; do
        out="$root/run_$run"; mkdir "$out"
        awk -v n="$points" -v start="$start" -v rng="$rng" -v seed="$((828968384+run))" '
            /^#/ {next}
            $1=="size" {print $1,120,120; next}
            $1=="num_single_site_stoc_upd" {print $1,86400; next}
            $1=="num_ns_meas" {print $1,n; next}
            $1=="start" {print $1,start; next}
            $1=="rng_start" {print $1,rng; next}
            $1=="rng_seed" {print $1,seed; next}
            {print}
        ' "$project/$template/run_0" > "$out/input.conf"
        for file in dati.dat topo.dat acceptance_rate.dat; do printf 'saved measurement\n' > "$out/$file"; done
        printf 'Theory: 2d CP^{N-1} model with N = 4\n' > "$out/log.dat"
        if [[ $ancestor != - ]]; then printf '../../job_%s/run_%s\n' "$ancestor" "$run" > "$out/parent_run"; fi
    done
done
existing="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22885157"
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
mkdir -p "$mcmc"
touch "$mcmc/completed"
printf '120\n' > "$mcmc/lattice"; printf '3\n' > "$mcmc/tasks"
for run in 0 1 2; do
    mkdir "$mcmc/run_$run"
    cp "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_$run.conf" "$mcmc/run_$run/input.conf"
    for file in dati.dat topo.dat; do printf 'saved MCMC measurement\n' > "$mcmc/run_$run/$file"; done
    printf 'Theory: 2d CP^{N-1} model with N = 4\n' > "$mcmc/run_$run/log.dat"
done
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
id=$((95001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${NS_STOC:-}" "${NS_EXECUTABLE:-}" \
    "${NS_INIT_SWEEPS:-}" "${NS_INIT_SPACING:-}" "${NS_SEED_BASE:-}" "$*" >> "$MOCK_RECORD"
printf '%s;mockcluster\n' "$id"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $* == *--export=ALL* ]]
printf '%s\n' "$*" >> "$MOCK_SRUN"
while [[ $1 == --* ]]; do shift; done
for ((task=0; task<SLURM_NTASKS; task++)); do SLURM_PROCID=$task "$@"; done
SH
cat > "$work/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
if [[ $1 == N4_volume_benchmark/scan_depth.py ]]; then printf 'synthetic_csv_header\n'; fi
SH
chmod +x "$work/bin/"{sbatch,srun,python}
export PATH="$work/bin:$PATH" NS_SCRATCH="$scratch" SLURM_SUBMIT_DIR="$project"
export MOCK_RECORD="$work/submissions.tsv" MOCK_SRUN="$work/srun.txt" MOCK_ANALYSIS="$work/analysis.txt"
touch "$MOCK_RECORD" "$MOCK_SRUN" "$MOCK_ANALYSIS"
cd "$project"
# The saved existing executable must be used, regardless of the checkout build.
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N4"
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_INIT_SWEEPS=1 NS_INIT_SPACING=1 \
    NS_EXECUTABLE=/missing NS_SEED_BASE=1 bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/submit.log"
campaign=$(awk -F ': ' '/^L120 eight-stream campaign records:/ {print $2}' "$work/submit.log")
[[ $(wc -l < "$MOCK_RECORD") == 5 && $(wc -l < "$campaign/jobs.tsv") == 6 ]]
[[ $(wc -l < "$campaign/planned_seeds.tsv") == 13 && $(cat "$campaign/analysis_job_id.txt") == 95005 ]]
awk -F '\t' 'NR>1 {if ($3<=0 || $3>=2147483399 || seen[$3]++) exit 1; n++} END {if(n!=12) exit 1}' "$campaign/planned_seeds.tsv"
[[ $(grep -c -- '--time=12:00:00.*120 150000' "$MOCK_RECORD") == 4 ]]
grep -q -- '--dependency=afterok:95001.*ns_L120_new1_to300k' "$MOCK_RECORD"
grep -q -- '--dependency=afterok:95003.*ns_L120_new2_to300k' "$MOCK_RECORD"
grep -q -- '--dependency=afterok:95002:95004.*analyze_L120_12x300k_ubelix.sh 22885157 95002 95004 22780263' "$MOCK_RECORD"
awk -F '\t' 'NR==2 || NR==4 {if ($2!="" || $3!="" || $4!="" || $5!="" || $6!="") exit 1}' "$MOCK_RECORD"
[[ -s "$campaign/analyze_command.txt" && -s "$campaign/existing_executable_sha256.txt" ]]
old_hash=$(sha256sum "$existing/run_0/dati.dat")
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
for batch in 1 2; do
    start_id=$((95001+2*(batch-1))) leaf_id=$((95002+2*(batch-1)))
    base=$(awk -F '\t' -v role="fresh${batch}_start" '$1==role {print $6}' "$campaign/jobs.tsv")
    NS_STOC=86400 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_EXECUTABLE="$existing/cpn_ns_N4" \
        NS_SEED_BASE="$base" SLURM_JOB_ID=$start_id bash N4_volume_benchmark/run_ubelix.sh 120 150000 > "$work/start$batch.log"
    start_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$start_id"
    [[ -f "$start_root/completed" ]]
    start_hash=$(sha256sum "$start_root/run_0/rng_state.dat")
    env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_EXECUTABLE -u NS_SEED_BASE \
        SLURM_JOB_ID=$leaf_id bash N4_volume_benchmark/run_ubelix.sh 120 150000 "$start_root" > "$work/leaf$batch.log"
    leaf_root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$leaf_id"
    [[ -f "$leaf_root/completed" && $(sha256sum "$start_root/run_0/rng_state.dat") == "$start_hash" ]]
    for run in 0 1 2 3; do
        for root in "$start_root" "$leaf_root"; do
            if [[ $root == "$start_root" ]]; then start=1 rng=0; else start=2 rng=1; fi
            awk -v seed="$((base+run))" -v start="$start" -v rng="$rng" '
                $1=="size" {a=($2==120 && $3==120)} $1=="beta" {b=($2==0.7)}
                $1=="num_ns_meas" {c=($2==150001)} $1=="num_single_site_stoc_upd" {d=($2==86400)}
                $1=="start" {e=($2==start)} $1=="rng_start" {f=($2==rng)} $1=="rng_seed" {g=($2==seed)}
                END {exit !(a&&b&&c&&d&&e&&f&&g)}' "$root/run_$run/input.conf"
        done
        [[ ! -e "$start_root/run_$run/parent_run" ]]
        [[ $(realpath "$leaf_root/run_$run/$(cat "$leaf_root/run_$run/parent_run")") == "$start_root/run_$run" ]]
    done
done
[[ $(sha256sum "$existing/run_0/dati.dat") == "$old_hash" ]]
[[ $(awk '$1=="rng_seed" {print $2}' "$existing"/run_*/input.conf "$scratch/ns_N4_beta0p7_volume_benchmark/L120/"job_9500{2,4}/run_*/input.conf | sort -u | wc -l) == 12 ]]
export SLURM_NTASKS=1 SLURM_JOB_ID=95005
bash N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh 22885157 95002 95004 22780263 > "$work/analysis.log"
output="$project/N4_L120_res/combined300_ns22885157_analysis_95005"
[[ -f "$output/completed" && $(wc -l < "$output/inputs.tsv") == 5 ]]
grep -q -- '--updates 180000 210000 240000 270000 300000 --targets 0.9 0.95 1.0' "$MOCK_ANALYSIS"
grep -q -- '--updates 300000 --beta 1.0 --bins 32' "$MOCK_ANALYSIS"
[[ $(grep -c 'utils/plot_mcmc.py' "$MOCK_ANALYSIS") == 2 ]]
if bash N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh 22885157 95002 95002 22780263 > "$work/duplicate_ids.log" 2>&1; then exit 1; fi
cfg="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_95002/run_0/input.conf"
cp "$cfg" "$work/config.saved"
sed -i -E 's/^rng_seed [0-9]+$/rng_seed 828968384/' "$cfg"
if SLURM_JOB_ID=95006 bash N4_volume_benchmark/analyze_L120_12x300k_ubelix.sh 22885157 95002 95004 22780263 > "$work/duplicate_seed.log" 2>&1; then exit 1; fi
cp "$work/config.saved" "$cfg"
# Every rejected preflight must leave the submission count unchanged.
mv "$existing/run_3/acceptance_rate.dat" "$work/acceptance.saved"
if bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/missing_history.log" 2>&1; then exit 1; fi
mv "$work/acceptance.saved" "$existing/run_3/acceptance_rate.dat"
sed -i 's/num_ns_meas 60001/num_ns_meas 60000/' "$existing/run_0/input.conf"
if bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/depth.log" 2>&1; then exit 1; fi
sed -i 's/num_ns_meas 60000/num_ns_meas 60001/' "$existing/run_0/input.conf"
sed -i 's/num_cool_step 50/num_cool_step 55/' "$project/$template/run_0"
if bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/template.log" 2>&1; then exit 1; fi
sed -i 's/num_cool_step 55/num_cool_step 50/' "$project/$template/run_0"
sed -i 's/N = 4/N = 21/' "$existing/cpn_ns_N4"
if bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$existing/cpn_ns_N4"
sed -i 's/N = 4/N = 21/' "$mcmc/run_0/log.dat"
if bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/wrong_mcmc_N.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$mcmc/run_0/log.dat"
[[ $(wc -l < "$MOCK_RECORD") == 5 ]]
if MOCK_FAIL_MATCH=ns_L120_new2_start bash N4_volume_benchmark/add_L120_8x300k_ubelix.sh > "$work/partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L120 eight-stream campaign records:/ {print $2}' "$work/partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 3 && $(wc -l < "$MOCK_RECORD") == 7 ]]
echo "Passed shell/LF, existing 300k histories, N=4 logs/binary, all 12 seeds, four simulation jobs/dependencies, 150k+150k configs and parent links, parent immutability, combined analysis routing, failure guards and partial-submission records. Local artifacts: $work"
