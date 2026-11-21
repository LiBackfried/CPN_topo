#!/bin/bash
# Local integration check with fake Slurm/Python; never contacts a scheduler.
set -euo pipefail
source_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
testroot=$(mktemp -d /tmp/cpn_robustness_test.XXXXXX)
cleanup() { [[ $testroot == /tmp/cpn_robustness_test.* ]] && rm -rf -- "$testroot"; }
trap cleanup EXIT
export MOCK_REPO="$testroot/repo"
mkdir -p "$MOCK_REPO/N4_volume_benchmark" "$MOCK_REPO/utils" "$testroot/bin"
for file in N4_volume_benchmark/{check_ensemble_robustness.py,compare_action_bins.py,scan_depth.py,robustness_L90_L120_ubelix.sh,submit_robustness_ubelix.sh} \
            analyze_nested_sampling.py utils/{nest_sampl.py,mcmc.py,cpn_io.py}; do
    cp "$source_repo/$file" "$MOCK_REPO/$file"
done
cat > "$testroot/bin/git" <<'EOF'
#!/bin/bash
case "$*" in
    *--show-toplevel*) printf '%s\n' "$MOCK_REPO" ;;
    *'rev-parse HEAD'*) echo mocked-revision ;;
    *'status --short'*) : ;;
    *) exit 2 ;;
esac
EOF
cat > "$testroot/bin/sbatch" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_REPO/sbatch_calls"
echo "$((21000000 + $(wc -l < "$MOCK_REPO/sbatch_calls")))"
EOF
cat > "$testroot/bin/python" <<'EOF'
#!/bin/bash
[[ $1 == -c ]] || exit 3
echo mocked-python
EOF
cat > "$testroot/bin/module" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$testroot/bin/srun" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_REPO/srun_calls"
while (( $# )); do
    if [[ $1 == --output ]]; then
        mkdir "$2"
        touch "$2/completed"
        exit 0
    fi
    shift
done
exit 4
EOF
chmod +x "$testroot/bin/"*
export PATH="$testroot/bin:$PATH"
bash "$MOCK_REPO/N4_volume_benchmark/submit_robustness_ubelix.sh" > "$testroot/submission.log"
[[ $(wc -l < "$MOCK_REPO/sbatch_calls") == 2 ]]
grep -q 'N4L90_robustness' "$MOCK_REPO/sbatch_calls"
grep -q 'N4L120_robustness' "$MOCK_REPO/sbatch_calls"
if bash "$MOCK_REPO/N4_volume_benchmark/submit_robustness_ubelix.sh" 66 > /dev/null 2>&1; then
    echo 'Invalid volume was accepted' >&2; exit 1
fi
export NS_SCRATCH="$testroot/scratch"
export SLURM_NTASKS=1 SLURM_CPUS_PER_TASK=1 SLURM_SUBMIT_DIR="$MOCK_REPO"
for lattice in 90 120; do
    if [[ $lattice == 90 ]]; then
        ids=(22810844 22810845 22810846); proposals=48600; mc_id=22635137; beta=0.95
        mc_group=mcmc_90_N4_beta0p95_3x100k
    else
        ids=(22885157 22904262 22904264); proposals=86400; mc_id=22780263; beta=1.0
        mc_group=mcmc_120_N4_beta1p0_3x100k
    fi
    for id in "${ids[@]}"; do
        root="$NS_SCRATCH/ns_N4_beta0p7_volume_benchmark/L$lattice/job_$id"
        mkdir -p "$root"; touch "$root/completed"
        echo "$lattice" > "$root/lattice"; echo 4 > "$root/tasks"
        for run in 0 1 2 3; do
            mkdir "$root/run_$run"
            printf '%s\n' "size $lattice $lattice" 'beta 0.7' 'theta 0' 'num_live_pts 50' \
                "num_single_site_stoc_upd $proposals" 'num_MC_step 20' 'meas_every 8' \
                'num_cool_step 50' 'meas_cool_every 5' > "$root/run_$run/input.conf"
        done
    done
    mcmc="$NS_SCRATCH/$mc_group/job_$mc_id"
    mkdir -p "$mcmc"; touch "$mcmc/completed"
    echo "$lattice" > "$mcmc/lattice"; echo 3 > "$mcmc/tasks"
    for run in 0 1 2; do
        mkdir "$mcmc/run_$run"
        printf '%s\n' "size $lattice $lattice" "beta $beta" 'theta 0' \
            'num_MC_step 1000000' 'meas_every 10' 'num_cool_step 50' 'meas_cool_every 5' > "$mcmc/run_$run/input.conf"
    done
    export SLURM_JOB_ID="99000$lattice"
    bash "$MOCK_REPO/N4_volume_benchmark/robustness_L90_L120_ubelix.sh" "$lattice" > "$testroot/worker_$lattice.log"
    [[ -f "$MOCK_REPO/N4_L${lattice}_res/robustness_steps12_$SLURM_JOB_ID/completed" ]]
    [[ -f "$MOCK_REPO/N4_L${lattice}_res/robustness_record_$SLURM_JOB_ID/source_sha256.txt" ]]
done
[[ $(wc -l < "$MOCK_REPO/srun_calls") == 2 ]]
grep -q -- '--updates 210000 --beta 0.95' "$MOCK_REPO/srun_calls"
grep -q -- '--updates 300000 --beta 1.0' "$MOCK_REPO/srun_calls"
grep -q 'job_22904262' "$MOCK_REPO/srun_calls"
grep -q 'job_22904264' "$MOCK_REPO/srun_calls"
sed -i 's/beta 1.0/beta 0.95/' "$mcmc/run_0/input.conf"
export SLURM_JOB_ID=99000999
if bash "$MOCK_REPO/N4_volume_benchmark/robustness_L90_L120_ubelix.sh" 120 > /dev/null 2>&1; then
    echo 'Mismatched MCMC beta was accepted' >&2; exit 1
fi
[[ $(wc -l < "$MOCK_REPO/srun_calls") == 2 ]]
echo 'Passed mocked submission and worker preflight checks for L90 and L120.'
