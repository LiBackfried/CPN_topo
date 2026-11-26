#!/bin/bash
# Submit from UBELIX. The optional argument overrides the cycles per chain.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || fail "Usage: bash $0 {L72-b061|L72-b060|L150-timing|L150-prior} [MC_CYCLES]"
mode=$1
case $mode in
    L72-b061) lattice=72; beta=0.61; stride=10; default_steps=200000; wall=08:00:00 ;;
    L72-b060) lattice=72; beta=0.60; stride=1;  default_steps=200000; wall=08:00:00 ;;
    L150-timing) lattice=150; beta=0.60; stride=1; default_steps=2000; wall=01:00:00 ;;
    L150-prior) lattice=150; beta=0.60; stride=1; default_steps=200000; wall=1-16:00:00 ;;
    *) fail "Unknown MCMC mode: $mode" ;;
esac
steps=${2:-$default_steps}
wall=${MCMC_WALLTIME:-$wall}
[[ $steps =~ ^[1-9][0-9]{0,6}$ ]] && (( steps % stride == 0 )) ||
    fail "MC cycles must be positive and divisible by measurement stride ($stride)."
if [[ $mode == L72-b061 ]]; then
    (( steps >= 25000 )) || fail 'The target reference needs at least 25,000 cycles for its burn-in scan.'
elif [[ $mode != L150-timing ]]; then
    (( steps >= 6000 )) || fail 'The prior analysis needs at least 6,000 cycles for its burn-in and spacing checks.'
fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
setup="$repo/N21_L72_ubelix_benchmark"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
executable="$repo/cpn_N21"
[[ $scratch == /* && -x $executable ]] || fail 'Use an absolute scratch path and build cpn_N21 first (build_N21_ubelix.sh mcmc).'
module purge
module load OpenSSL/1.1
info=$("$executable" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info" || fail 'Expected an N=21 executable.'
grep -Eq '^Compiled from main (.*/)?cpn\.c$' <<< "$info" || fail 'Expected the regular cpn MCMC executable.'
mkdir -p "$scratch" "$repo/N21_benchmark_results"
campaign=$(mktemp -d "$scratch/mcmc_N21_${mode}.XXXXXXXX")
snapshot="$campaign/snapshot"
mkdir -p "$snapshot/utils"
cp "$setup/"{mcmc_job_ubelix.sh,analyze_mcmc.py} "$snapshot/"
cp "$repo/utils/"{cpn_io.py,mcmc.py} "$snapshot/utils/"
cp "$executable" "$snapshot/cpn_N21"
if [[ -r $executable.build_info.txt ]]; then cp "$executable.build_info.txt" "$snapshot/"; fi
(cd "$snapshot"; sha256sum mcmc_job_ubelix.sh analyze_mcmc.py utils/*.py cpn_N21 > sources.sha256)
cd "$repo"
for name in ${!SBATCH_@}; do unset "$name"; done
echo "Scratch campaign: $campaign"
sim=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --mem-per-cpu=2G \
    --time="$wall" --job-name="N21_${mode}" --output="$campaign/sim_%j.out" \
    --error="$campaign/sim_%j.err" "$snapshot/mcmc_job_ubelix.sh" run "$mode" "$campaign" "$lattice" "$beta" "$steps" "$stride")
sim=${sim%%;*}
[[ $sim =~ ^[0-9]+$ ]] || fail "Unexpected simulation ID: $sim"
printf '%s\n' "$sim" > "$campaign/simulation_job_id.txt"
analysis=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 --mem-per-cpu=4G \
    --time=01:00:00 --job-name="N21_${mode}_analysis" --dependency="afterok:$sim" \
    --output="$campaign/analysis_%j.out" --error="$campaign/analysis_%j.err" \
    "$snapshot/mcmc_job_ubelix.sh" analyze "$mode" "$campaign" "$sim") ||
    fail "Analysis submission failed. Simulation job $sim was submitted."
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected analysis ID: $analysis"
output="$repo/N21_benchmark_results/mcmc_${mode}_$analysis"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
printf '%s\n' "$output" > "$campaign/analysis_output.txt"
echo "Simulation job: $sim. Dependent analysis job: $analysis."
echo "Worktree results: $output"
echo "sacct -j $sim,$analysis --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS"
