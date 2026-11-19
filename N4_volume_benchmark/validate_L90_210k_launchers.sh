#!/bin/bash
# Local Slurm/Python mocks: no real submissions or scientific measurements.
set -euo pipefail
trap 'printf "Validation failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-L90-210k-launchers.XXXXXXXX)
project="$work/project"
scratch="$work/scratch"
mkdir -p "$project/N4_volume_benchmark" "$work/bin" "$scratch"
git -C "$repo" init -q "$project"
cp "$repo/N4_volume_benchmark/"{extend_L90_12x210k_ubelix.sh,analyze_L90_12x210k_ubelix.sh,run_ubelix.sh} "$project/N4_volume_benchmark/"
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template"
cp "$repo/$template/run_0" "$project/$template/run_0"
for file in "$repo/N4_volume_benchmark/"{extend_L90_12x210k_ubelix.sh,analyze_L90_12x210k_ubelix.sh,validate_L90_210k_launchers.sh,run_ubelix.sh}; do
    bash -n "$file"
    ! LC_ALL=C grep -q $'\r' "$file"
done
module() { return 0; }
export -f module
cat > "$project/cpn_ns_N4" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
for file in dati.dat topo.dat log.dat live_energy.dat rng_state.dat; do printf 'mock output\n' > "$file"; done
for live in {0..49}; do printf 'mock live configuration\n' > "conf.dat_live_$live"; done
SH
chmod +x "$project/cpn_ns_N4"
old="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_22635195"
parent="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_22779059"
for root in "$old" "$parent"; do
    mkdir -p "$root"
    touch "$root/completed"
    printf '90\n' > "$root/lattice"; printf '4\n' > "$root/tasks"
    cp "$project/cpn_ns_N4" "$root/cpn_ns_N4"
    for run in 0 1 2 3; do
        mkdir "$root/run_$run"
        if [[ $root == "$old" ]]; then points=80001 start=1 rng=0; else points=60001 start=2 rng=1; fi
        awk -v points="$points" -v start="$start" -v rng="$rng" -v seed="$((824326240+run))" '
            /^#/ {next}
            $1=="size" {print $1,90,90; next}
            $1=="num_single_site_stoc_upd" {print $1,48600; next}
            $1=="num_ns_meas" {print $1,points; next}
            $1=="start" {print $1,start; next}
            $1=="rng_start" {print $1,rng; next}
            $1=="rng_seed" {print $1,seed; next}
            {print}
        ' "$project/$template/run_0" > "$root/run_$run/input.conf"
        printf 'saved live energies\n' > "$root/run_$run/live_energy.dat"
        printf 'saved RNG state\n' > "$root/run_$run/rng_state.dat"
        for live in {0..49}; do printf 'saved live %s\n' "$live" > "$root/run_$run/conf.dat_live_$live"; done
        if [[ $root == "$parent" ]]; then printf '../../job_22635195/run_%s\n' "$run" > "$root/run_$run/parent_run"; fi
    done
done
mcmc="$scratch/mcmc_90_N4_beta0p95_3x100k/job_22635137"
mkdir -p "$mcmc"
touch "$mcmc/completed"
printf '90\n' > "$mcmc/lattice"; printf '3\n' > "$mcmc/tasks"
for run in 0 1 2; do
    mkdir "$mcmc/run_$run"
    cp "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_$run.conf" "$mcmc/run_$run/input.conf"
done
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
id=$((94001+$(wc -l < "$MOCK_RECORD")))
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
# The parent's saved N=4 executable must be reused even if the checkout's build differs.
sed -i 's/N = 4/N = 21/' "$project/cpn_ns_N4"
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_INIT_SWEEPS=1 NS_INIT_SPACING=1 \
    NS_EXECUTABLE=/missing NS_SEED_BASE=1 bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/submit.log"
campaign=$(awk -F ': ' '/^L90 12-stream campaign records:/ {print $2}' "$work/submit.log")
[[ $(wc -l < "$MOCK_RECORD") == 4 && $(wc -l < "$campaign/jobs.tsv") == 5 ]]
[[ $(wc -l < "$campaign/planned_seeds.tsv") == 13 && $(cat "$campaign/analysis_job_id.txt") == 94004 ]]
awk -F '\t' 'NR>1 {if ($3<=0 || $3>=2147483399 || seen[$3]++) exit 1; n++} END {if(n!=12) exit 1}' "$campaign/planned_seeds.tsv"
awk -F '\t' 'NR==1 {exit !($2=="" && $3=="" && $4=="" && $5=="" && $6=="")}' "$MOCK_RECORD"
grep -q -- '--time=04:00:00.*90 70000' "$MOCK_RECORD"
[[ $(grep -c -- '--time=08:00:00.*90 210000' "$MOCK_RECORD") == 2 ]]
grep -q -- '--dependency=afterok:94001:94002:94003' "$MOCK_RECORD"
[[ -s "$campaign/analyze_command.txt" && -s "$campaign/parent_executable_sha256.txt" ]]
parent_hash=$(sha256sum "$parent/run_0/rng_state.dat")
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_EXECUTABLE -u NS_SEED_BASE \
    SLURM_JOB_ID=94001 bash N4_volume_benchmark/run_ubelix.sh 90 70000 "$parent" > "$work/continue.log"
continued="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_94001"
[[ -f "$continued/completed" && $(sha256sum "$parent/run_0/rng_state.dat") == "$parent_hash" ]]
for run in 0 1 2 3; do
    cfg="$continued/run_$run/input.conf"
    awk '$1=="num_ns_meas" {a=($2==70001)} $1=="start" {b=($2==2)}
         $1=="rng_start" {c=($2==1)} $1=="num_single_site_stoc_upd" {d=($2==48600)}
         END {exit !(a&&b&&c&&d)}' "$cfg"
    [[ $(realpath "$continued/run_$run/$(cat "$continued/run_$run/parent_run")") == "$parent/run_$run" ]]
done
for batch in 1 2; do
    id=$((94001+batch))
    base=$(awk -F '\t' -v role="fresh$batch" '$1==role {print $6}' "$campaign/jobs.tsv")
    NS_STOC=48600 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_EXECUTABLE="$parent/cpn_ns_N4" \
        NS_SEED_BASE="$base" SLURM_JOB_ID=$id bash N4_volume_benchmark/run_ubelix.sh 90 210000 > "$work/fresh$batch.log"
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_$id"
    [[ -f "$root/completed" ]]
    for run in 0 1 2 3; do
        awk -v seed="$((base+run))" '$1=="size" {a=($2==90 && $3==90)} $1=="beta" {b=($2==0.7)}
             $1=="num_ns_meas" {c=($2==210001)} $1=="num_single_site_stoc_upd" {d=($2==48600)}
             $1=="start" {e=($2==1)} $1=="rng_start" {f=($2==0)} $1=="rng_seed" {g=($2==seed)}
             END {exit !(a&&b&&c&&d&&e&&f&&g)}' "$root/run_$run/input.conf"
        [[ ! -e "$root/run_$run/parent_run" ]]
    done
done
[[ $(awk '$1=="rng_seed" {print $2}' "$scratch/ns_N4_beta0p7_volume_benchmark/L90/"job_9400{1,2,3}/run_*/input.conf | sort -u | wc -l) == 12 ]]
export SLURM_NTASKS=1 SLURM_JOB_ID=94004
bash N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh 94001 94002 94003 22635137 > "$work/analysis.log"
output="$project/N4_L90_res/combined210_ns94001_analysis_94004"
[[ -f "$output/completed" && $(wc -l < "$output/inputs.tsv") == 5 ]]
grep -q -- '--updates 100000 120000 140000 160000 180000 200000 210000 --targets 0.9 0.95 1.0 --bootstrap 200' "$MOCK_ANALYSIS"
grep -q -- '--updates 210000 --beta 0.95 --bins 32' "$MOCK_ANALYSIS"
[[ $(grep -c 'utils/plot_mcmc.py' "$MOCK_ANALYSIS") == 2 ]]
if bash N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh 94001 94001 94003 22635137 > "$work/duplicate_ids.log" 2>&1; then exit 1; fi
seed_old=$(awk '$1=="rng_seed" {print $2}' "$continued/run_0/input.conf")
fresh_cfg="$scratch/ns_N4_beta0p7_volume_benchmark/L90/job_94002/run_0/input.conf"
cp "$fresh_cfg" "$work/fresh_cfg.saved"
sed -i -E "s/^rng_seed [0-9]+$/rng_seed $seed_old/" "$fresh_cfg"
if SLURM_JOB_ID=94005 bash N4_volume_benchmark/analyze_L90_12x210k_ubelix.sh 94001 94002 94003 22635137 > "$work/duplicate_analysis_seed.log" 2>&1; then exit 1; fi
cp "$work/fresh_cfg.saved" "$fresh_cfg"
# Each preflight failure below must leave the submission count unchanged.
mv "$parent/run_3/conf.dat_live_49" "$work/live.saved"
if bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/missing_checkpoint.log" 2>&1; then exit 1; fi
mv "$work/live.saved" "$parent/run_3/conf.dat_live_49"
sed -i 's/num_ns_meas 60001/num_ns_meas 60000/' "$parent/run_0/input.conf"
if bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/depth.log" 2>&1; then exit 1; fi
sed -i 's/num_ns_meas 60000/num_ns_meas 60001/' "$parent/run_0/input.conf"
sed -i 's/num_cool_step 50/num_cool_step 55/' "$project/$template/run_0"
if bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/template.log" 2>&1; then exit 1; fi
sed -i 's/num_cool_step 55/num_cool_step 50/' "$project/$template/run_0"
sed -i 's/N = 4/N = 21/' "$parent/cpn_ns_N4"
if bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$parent/cpn_ns_N4"
sed -i 's/rng_seed 824326241/rng_seed 824326240/' "$parent/run_1/input.conf"
if bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/inherited_seed.log" 2>&1; then exit 1; fi
sed -i 's/rng_seed 824326240/rng_seed 824326241/' "$parent/run_1/input.conf"
[[ $(wc -l < "$MOCK_RECORD") == 4 ]]
if MOCK_FAIL_MATCH=ns_L90_new2_210k bash N4_volume_benchmark/extend_L90_12x210k_ubelix.sh > "$work/partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L90 12-stream campaign records:/ {print $2}' "$work/partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 3 && $(wc -l < "$MOCK_RECORD") == 6 ]]
echo "Passed shell/LF, 140k ancestor/checkpoint preflight, environment cleanup, parent executable reuse, all 12 seeds, continuation/fresh configs and counts, parent immutability, three-job dependency, combined analysis routing, rejection guards and partial-submission records. Local artifacts: $work"
