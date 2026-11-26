#!/bin/bash
# Reuse the tested local Slurm fixture; no remote calls or production runs.
set -euo pipefail
fixture_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
source "$fixture_dir/test_sampling_validation_launchers.sh"
for file in add_L120_proposals_8to24_ubelix.sh analyze_L120_proposals24_ubelix.sh analyze_sampling_validation.py plot_L120_proposal_charges.py plot_charge_distributions.py export_charge_moments.py; do
    cp "$repo/N4_volume_benchmark/$file" "$project/N4_volume_benchmark/"
    if [[ $file == *.sh ]]; then bash -n "$project/N4_volume_benchmark/$file"; fi
    ! LC_ALL=C grep -q $'\r' "$project/N4_volume_benchmark/$file"
done
# The saved baseline leaves are represented by complete 300k single segments.
for id in 22885157 22904262 22904264 23350703 23350705 23350707; do
    for run in 0 1 2 3; do
        path="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id/run_$run"
        sed -i 's/^num_ns_meas .*/num_ns_meas 300001/' "$path/input.conf"
        for file in dati.dat topo.dat acceptance_rate.dat; do echo mock > "$path/$file"; done
        echo 'Theory: 2d CP^{N-1} model with N = 4' > "$path/log.dat"
    done
done
# Old control leaves inherit the three 100k-stage histories exercised above.
for spec in '97005 23502237' '97008 23502240'; do
    read -r from to <<< "$spec"
    cp -a "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$from" "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$to"
done
for run in 0 1 2; do
    for file in dati.dat topo.dat; do echo mock > "$mcmc/run_$run/$file"; done
    echo 'Theory: 2d CP^{N-1} model with N = 4' > "$mcmc/run_$run/log.dat"
done
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ! -v SBATCH_NTASKS && ! -v SBATCH_TIMELIMIT ]]
if [[ -n ${MOCK_FAIL_MATCH:-} && $* == *"$MOCK_FAIL_MATCH"* ]]; then exit 1; fi
id=$((98001+$(wc -l < "$MOCK_RECORD")))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${NS_STOC:-}" "${NS_INIT_SWEEPS:-}" "${NS_INIT_SPACING:-}" "${NS_SEED_BASE:-}" "${NS_EXECUTABLE:-}" "$*" >> "$MOCK_RECORD"
echo "$id;mockcluster"
SH
cat > "$work/bin/od" <<'SH'
#!/bin/bash
n=$(cat "$MOCK_RANDOM_COUNT"); echo "$((n+1))" > "$MOCK_RANDOM_COUNT"
words=(99 2126073773 200000000 100000000 100000000 300000000 400000000 500000000 600000000)
if ((n<9)); then echo "${words[$n]}"; else echo "$((700000000+n*100))"; fi
SH
chmod +x "$work/bin/"{sbatch,od}
: > "$MOCK_RECORD"; : > "$MOCK_ANALYSIS"; echo 0 > "$MOCK_RANDOM_COUNT"
unset NS_STOC NS_INIT_SWEEPS NS_INIT_SPACING NS_SEED_BASE NS_EXECUTABLE
SBATCH_NTASKS=1 SBATCH_TIMELIMIT=1 NS_STOC=1 NS_EXECUTABLE=/missing \
    bash N4_volume_benchmark/add_L120_proposals_8to24_ubelix.sh > "$work/expand_submit.log"
campaign=$(awk -F ': ' '/^L120 doubled-proposal 24-stream campaign records:/ {print $2}' "$work/expand_submit.log")
[[ $(wc -l < "$MOCK_RECORD") == 13 && $(wc -l < "$campaign/jobs.tsv") == 14 ]]
[[ $(wc -l < "$campaign/existing_streams.tsv") == 33 && $(wc -l < "$campaign/excluded_seeds.tsv") == 40 ]]
[[ $(wc -l < "$campaign/planned_seeds.tsv") == 17 && $(<"$MOCK_RANDOM_COUNT") == 9 ]]
awk -F '\t' 'NR==FNR {if(FNR>1) used[$2]=1; next} FNR>1 {if($3<=0 || $3>=2147483399 || used[$3]++) exit 1; n++} END {if(n!=16) exit 1}' \
    "$campaign/excluded_seeds.tsv" "$campaign/planned_seeds.tsv"
grep -q -- '--dependency=afterok:98003:98006:98009:98012.*analyze_L120_proposals24_ubelix.sh 98003 98006 98009 98012' "$MOCK_RECORD"
awk -F '\t' 'NR<=12 && NR%3!=1 {for(i=2;i<=6;i++) if($i!="") exit 1}' "$MOCK_RECORD"
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
old_hash=$(sha256sum "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/run_0/rng_state.dat")
for batch in 1 2 3 4; do
    base=$(awk -F '\t' -v batch="$batch" '$1==batch && $2==0 {print $3}' "$campaign/planned_seeds.tsv")
    parent=
    for stage in 1 2 3; do
        id=$((98001+3*(batch-1)+stage-1)); root="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$id"
        if [[ -z $parent ]]; then
            NS_STOC=172800 NS_INIT_SWEEPS=20 NS_INIT_SPACING=8 NS_SEED_BASE="$base" \
                NS_EXECUTABLE="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/cpn_ns_N4" \
                SLURM_JOB_ID=$id bash N4_volume_benchmark/run_ubelix.sh 120 100000 > "$work/expand${batch}_${stage}.log"
            start=1 rng=0
        else
            before=$(sha256sum "$parent/run_0/rng_state.dat")
            env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_SEED_BASE -u NS_EXECUTABLE \
                SLURM_JOB_ID=$id bash N4_volume_benchmark/run_ubelix.sh 120 100000 "$parent" > "$work/expand${batch}_${stage}.log"
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
[[ $(sha256sum "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/run_0/rng_state.dat") == "$old_hash" ]]
export SLURM_NTASKS=1 SLURM_JOB_ID=98013
bash N4_volume_benchmark/analyze_L120_proposals24_ubelix.sh 98003 98006 98009 98012 > "$work/expand_analysis.log"
output="$project/N4_L120_res/proposals172800_24streams_analysis_98013"
[[ -f "$output/completed" && -f "$output/proposal_comparison/completed" && -f "$output/charge_distributions/completed" ]]
grep -q -- '--control .*job_23502237.*job_23502240.*job_98003.*job_98012.*--control-streams 24 --stream-orderings 4' "$MOCK_ANALYSIS"
grep -q -- 'plot_L120_proposal_charges.py analyze.*--comparison.*proposal_comparison/inputs.json' "$MOCK_ANALYSIS"
if SLURM_JOB_ID=98014 bash N4_volume_benchmark/analyze_L120_proposals24_ubelix.sh 98003 98006 98009 98009 > "$work/expand_duplicate.log" 2>&1; then exit 1; fi
cfg="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/run_0/input.conf"
cp "$cfg" "$work/control_saved"
sed -i 's/num_ns_meas 100001/num_ns_meas 100000/' "$cfg"
if bash N4_volume_benchmark/add_L120_proposals_8to24_ubelix.sh > "$work/expand_bad_depth.log" 2>&1; then exit 1; fi
cp "$work/control_saved" "$cfg"
sed -i 's/N = 4/N = 21/' "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/cpn_ns_N4"
if bash N4_volume_benchmark/add_L120_proposals_8to24_ubelix.sh > "$work/expand_bad_N.log" 2>&1; then exit 1; fi
sed -i 's/N = 21/N = 4/' "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_23502237/cpn_ns_N4"
[[ $(wc -l < "$MOCK_RECORD") == 13 ]]
if MOCK_FAIL_MATCH=ns_L120_p172800_add16_b3_s1 bash N4_volume_benchmark/add_L120_proposals_8to24_ubelix.sh > "$work/expand_partial.log" 2>&1; then exit 1; fi
partial=$(awk -F ': ' '/^L120 doubled-proposal 24-stream campaign records:/ {print $2}' "$work/expand_partial.log")
[[ $(wc -l < "$partial/jobs.tsv") == 7 && $(wc -l < "$MOCK_RECORD") == 19 ]]
echo "Passed: 16 fresh streams, 12 simulation stages, 13 submissions, 300k ancestry/seed checks, inherited RNG states, protected old streams, matched analysis and failure records. Mock artifacts: $work"
