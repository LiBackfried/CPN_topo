#!/bin/bash
# Local mocked Slurm integration; no remote submissions or simulations.
set -euo pipefail
trap 'printf "Validation failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-sampling-validation.XXXXXXXX)
project="$work/project" scratch="$work/scratch"
mkdir -p "$project/N4_volume_benchmark" "$project/utils" "$work/bin" "$scratch"
git init -q "$project"
git -C "$project" -c user.name=Mock -c user.email=mock@example.invalid commit --allow-empty -qm Fixture
for name in submit_L120_sampling_validation_ubelix.sh run_L120_source_init_ubelix.sh analyze_L120_sampling_validation_ubelix.sh run_ubelix.sh analyze_sampling_validation.py; do
    cp "$repo/N4_volume_benchmark/$name" "$project/N4_volume_benchmark/"
    if [[ $name == *.sh ]]; then bash -n "$project/N4_volume_benchmark/$name"; fi
    ! LC_ALL=C grep -q $'\r' "$project/N4_volume_benchmark/$name"
done
template=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
mkdir -p "$project/$template" "$project/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k"
cp "$repo/$template/run_0" "$project/$template/"
cp "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_0.conf" "$project/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/"
for name in check_ensemble_robustness.py scan_stream_count.py scan_depth.py compare_action_bins.py; do touch "$project/N4_volume_benchmark/$name"; done
touch "$project/analyze_nested_sampling.py"
for name in nest_sampl.py mcmc.py cpn_io.py; do touch "$project/utils/$name"; done
module() { return 0; }; export -f module
cat > "$work/ns_binary" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
for file in dati.dat topo.dat acceptance_rate.dat live_energy.dat rng_state.dat; do echo mock > "$file"; done
echo 'Theory: 2d CP^{N-1} model with N = 4' > log.dat
for live in {0..49}; do echo live > "conf.dat_live_$live"; done
SH
cat > "$work/mc_binary" <<'SH'
#!/bin/bash
set -euo pipefail
if (( $# == 0 )); then echo 'Compiled with N = 4'; exit 1; fi
steps=$(awk '$1=="num_MC_step" {print $2}' input.conf)
awk -v n="$steps" 'BEGIN {for(i=1;i<=n;i++) print i,0.6,10,4}' > dati.dat
awk -v n="$steps" 'BEGIN {for(i=1;i<=n;i++) for(j=0;j<=50;j+=5) print i,j,0,0,0}' > topo.dat
for file in conf.dat rng_state.dat; do echo mock > "$file"; done
echo 'Theory: 2d CP^{N-1} model with N = 4' > log.dat
SH
chmod +x "$work/"{ns_binary,mc_binary}
index=0
for id in 22885157 22904262 22904264 23350703 23350705 23350707; do
    root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
    mkdir -p "$root"; touch "$root/completed"; echo 120 > "$root/lattice"; echo 4 > "$root/tasks"
    cp "$work/ns_binary" "$root/cpn_ns_N4"
    for run in 0 1 2 3; do
        mkdir "$root/run_$run"
        awk -v seed="$((100+4*index+run))" '
            $1=="size" {print $1,120,120; next}
            $1=="rng_seed" {print $1,seed; next}
            $1=="num_single_site_stoc_upd" {print $1,86400; next}
            {print}
        ' "$project/$template/run_0" > "$root/run_$run/input.conf"
    done
    index=$((index+1))
done
existing="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_22885157"
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_22780263"
mkdir -p "$mcmc"; touch "$mcmc/completed"; echo 120 > "$mcmc/lattice"; echo 3 > "$mcmc/tasks"
cp "$work/mc_binary" "$mcmc/cpn_N4"
for run in 0 1 2; do
    mkdir "$mcmc/run_$run"
    cp "$repo/N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_$run.conf" "$mcmc/run_$run/input.conf"
done
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
id=$((97001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${NS_STOC:-}" "${NS_INIT_SWEEPS:-}" "${NS_INIT_SPACING:-}" "${NS_SEED_BASE:-}" "${NS_EXECUTABLE:-}" "$*" >> "$MOCK_RECORD"
echo "$id;mockcluster"
SH
cat > "$work/bin/srun" <<'SH'
#!/bin/bash
set -euo pipefail
while [[ $1 == --* ]]; do shift; done
for ((task=0;task<SLURM_NTASKS;task++)); do SLURM_PROCID=$task "$@"; done
SH
cat > "$work/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ANALYSIS"
while (( $# )); do
    if [[ $1 == --output ]]; then mkdir "$2"; touch "$2/completed"; break; fi
    shift
done
SH
cat > "$work/bin/od" <<'SH'
#!/bin/bash
n=$(cat "$MOCK_RANDOM_COUNT")
echo "$((n+1))" > "$MOCK_RANDOM_COUNT"
words=(99 100000000 100000000 200000000 300000000)
if ((n<5)); then echo "${words[$n]}"; else echo "$((400000000+n*100))"; fi
SH
chmod +x "$work/bin/"{sbatch,srun,python,od}
export PATH="$work/bin:$PATH" NS_SCRATCH="$scratch" SLURM_SUBMIT_DIR="$project"
export MOCK_RECORD="$work/submissions.tsv" MOCK_ANALYSIS="$work/analysis.txt" MOCK_RANDOM_COUNT="$work/random_count"
touch "$MOCK_RECORD" "$MOCK_ANALYSIS"; echo 0 > "$MOCK_RANDOM_COUNT"
cd "$project"
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 bash N4_volume_benchmark/submit_L120_sampling_validation_ubelix.sh > "$work/submit.log"
campaign=$(awk -F ': ' '/^L120 sampling-validation records:/ {print $2}' "$work/submit.log")
[[ $(wc -l < "$MOCK_RECORD") == 9 && $(wc -l < "$campaign/jobs.tsv") == 10 ]]
[[ $(wc -l < "$campaign/planned_seeds.tsv") == 37 && $(<"$MOCK_RANDOM_COUNT") == 5 ]]
awk -F '\t' 'NR>1 {if($3<=0 || $3>=2147483399 || seen[$3]++) exit 1; n++} END {if(n!=36) exit 1}' "$campaign/planned_seeds.tsv"
grep -q -- '--dependency=afterok:97001.*source 97001' "$MOCK_RECORD"
grep -q -- '--dependency=afterok:97005:97008.*proposals 97005 97008' "$MOCK_RECORD"
awk -F '\t' 'NR==4 || NR==5 || NR==7 || NR==8 {for(i=2;i<=6;i++) if($i!="") exit 1}' "$MOCK_RECORD"
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
base=$(awk -F '\t' '$1=="source" && $2==0 {print $3}' "$campaign/planned_seeds.tsv")
SLURM_JOB_ID=97001 bash N4_volume_benchmark/run_L120_source_init_ubelix.sh "$base" 10000 > "$work/source.log"
source_root="$scratch/mcmc_120_N4_beta0p7_initpilot/job_97001"
[[ -f "$source_root/completed" ]]
for run in 0 1 2 3; do
    if ((run<2)); then start=0; else start=1; fi
    awk -v start="$start" -v seed="$((base+run))" '
        {v[$1]=$2} END {exit !(v["start"]==start && v["rng_seed"]==seed && v["beta"]==.7 && v["meas_every"]==1 && v["num_MC_step"]==10000)}' "$source_root/run_$run/input.conf"
done
old_hash=$(sha256sum "$existing/run_0/input.conf")
for batch in 1 2; do
    base=$(awk -F '\t' -v role="ns$batch" '$1==role && $2==0 {print $3}' "$campaign/planned_seeds.tsv")
    parent=
    for stage in 1 2 3; do
        id=$((97003+3*(batch-1)+stage-1))
        root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
        if [[ -z $parent ]]; then
            NS_STOC=172800 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" NS_EXECUTABLE="$existing/cpn_ns_N4" \
                SLURM_JOB_ID=$id bash N4_volume_benchmark/run_ubelix.sh 120 100000 > "$work/ns${batch}_${stage}.log"
            start=1 rng=0
        else
            before=$(sha256sum "$parent/run_0/rng_state.dat")
            env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
                SLURM_JOB_ID=$id bash N4_volume_benchmark/run_ubelix.sh 120 100000 "$parent" > "$work/ns${batch}_${stage}.log"
            [[ $(sha256sum "$parent/run_0/rng_state.dat") == "$before" ]]
            start=2 rng=1
        fi
        [[ -f "$root/completed" ]]
        for run in 0 1 2 3; do
            awk -v start="$start" -v rng="$rng" -v seed="$((base+run))" '
                {v[$1]=$2} END {exit !(v["num_ns_meas"]==100001 && v["num_single_site_stoc_upd"]==172800 &&
                v["num_MC_step"]==20 && v["meas_every"]==8 && v["start"]==start && v["rng_start"]==rng && v["rng_seed"]==seed)}' "$root/run_$run/input.conf"
            if [[ -n $parent ]]; then [[ $(realpath "$root/run_$run/$(cat "$root/run_$run/parent_run")") == "$parent/run_$run" ]]; fi
        done
        parent=$root
    done
done
[[ $(sha256sum "$existing/run_0/input.conf") == "$old_hash" ]]
export SLURM_NTASKS=1
SLURM_JOB_ID=97002 bash N4_volume_benchmark/analyze_L120_sampling_validation_ubelix.sh source 97001 > "$work/source_analysis.log"
SLURM_JOB_ID=97009 bash N4_volume_benchmark/analyze_L120_sampling_validation_ubelix.sh proposals 97005 97008 > "$work/proposals_analysis.log"
grep -q -- 'source --mcmc.*job_97001' "$MOCK_ANALYSIS"
grep -q -- 'proposals --baseline.*--control.*job_97005.*job_97008.*--bootstrap 200 --joint-draws 1000' "$MOCK_ANALYSIS"
cfg="$existing/run_1/input.conf"; cp "$cfg" "$work/config.saved"
sed -i 's/rng_seed 101/rng_seed 100/' "$cfg"
if bash N4_volume_benchmark/submit_L120_sampling_validation_ubelix.sh > "$work/duplicate.log" 2>&1; then exit 1; fi
cp "$work/config.saved" "$cfg"
sed -i 's/N = 4/N = 21/' "$mcmc/cpn_N4"
if bash N4_volume_benchmark/submit_L120_sampling_validation_ubelix.sh > "$work/wrongN.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$mcmc/cpn_N4"
[[ $(wc -l < "$MOCK_RECORD") == 9 ]]
if MOCK_FAIL_MATCH=ns_L120_p172800_b2_s1 bash N4_volume_benchmark/submit_L120_sampling_validation_ubelix.sh ns > "$work/partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L120 sampling-validation records:/ {print $2}' "$work/partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 4 && $(wc -l < "$MOCK_RECORD") == 12 ]]
echo "Passed: nine submissions, seed collisions, hot/cold pilots, six NS stages, immutable parents, dependency wiring, separate analyses and rejection/partial-submission guards. Mock artifacts: $work"
