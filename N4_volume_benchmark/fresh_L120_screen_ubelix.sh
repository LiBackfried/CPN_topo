#!/bin/bash
# Submission driver: run with bash on a UBELIX login node, not as a batch worker.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 0 ]] || fail "Usage: bash $0"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
ns_exe=${NS_EXECUTABLE:-$repo/cpn_ns_N4}
module load OpenSSL/1.1
for executable in "$ns_exe" "$repo/cpn_N4"; do
    [[ $executable == /* && -x $executable ]] || fail 'Existing N=4 NS and MCMC executables are required.'
    info=$("$executable" 2>&1 || true)
    grep -Fxq 'Compiled with N = 4' <<< "$info" || fail "Expected N=4: $executable"
done
for file in N4_volume_benchmark/run_ubelix.sh N4_volume_benchmark/analyze_L120_ubelix.sh \
    N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/{run_ubelix.sh,run_0.conf,run_1.conf,run_2.conf}; do
    [[ -r $file ]] || fail "Missing launcher/config: $file"
done
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Submission records must resolve inside repository N4_L120_res.'
campaign=$(mktemp -d "$results/campaign.XXXXXX")
manifest="$campaign/jobs.tsv"
printf 'kind\tjob_id\tdirectory\n' > "$manifest"
# Do not inherit options from a parent sbatch invocation or Open OnDemand session.
for name in ${!SBATCH_@}; do unset "$name"; done
export NS_SCRATCH="$scratch" NS_EXECUTABLE="$ns_exe" NS_STOC=86400
export NS_INIT_SWEEPS=20 NS_INIT_SPACING=8
unset NS_SEED_BASE
echo "L120 campaign records: $campaign"
ns_job=$(sbatch --parsable --export=ALL --ntasks=4 --cpus-per-task=1 --time=12:00:00 \
    --job-name=N4L120_b07_screen --output="$campaign/slurm_ns_%j.out" \
    N4_volume_benchmark/run_ubelix.sh 120 120000) || fail "NS submission failed. See $manifest"
ns_job=${ns_job%%;*}
[[ $ns_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $ns_job (inspect squeue before retrying)."
printf 'ns\t%s\t%s\n' "$ns_job" "$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$ns_job" >> "$manifest"
echo "Submitted NS $ns_job: four streams, 120000 updates, 86400 proposals/update"
mc_job=$(sbatch --parsable --export=ALL --ntasks=3 --cpus-per-task=1 --time=16:00:00 \
    --output="$campaign/slurm_mcmc_%j.out" \
    N4_volume_benchmark/mcmc_120_N4_beta1p0_3x100k/run_ubelix.sh) ||
    fail "NS $ns_job was submitted; MCMC submission failed. See $manifest before retrying."
mc_job=${mc_job%%;*}
[[ $mc_job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $mc_job (inspect squeue before retrying)."
printf 'mcmc\t%s\t%s\n' "$mc_job" "$scratch/mcmc_120_N4_beta1p0_3x100k/job_$mc_job" >> "$manifest"
echo "Submitted MCMC $mc_job: three beta=1.0 chains, 1000000 MC steps each"
printf -v retry 'sbatch --export=ALL --ntasks=1 --cpus-per-task=1 --dependency=afterok:%s:%s --output=%q N4_volume_benchmark/analyze_L120_ubelix.sh %s %s' \
    "$ns_job" "$mc_job" "$campaign/slurm_analysis_%j.out" "$ns_job" "$mc_job"
printf '%s\n' "$retry" > "$campaign/analyze_command.txt"
analysis=$(sbatch --parsable --export=ALL --ntasks=1 --cpus-per-task=1 \
    --dependency="afterok:$ns_job:$mc_job" --output="$campaign/slurm_analysis_%j.out" \
    N4_volume_benchmark/analyze_L120_ubelix.sh "$ns_job" "$mc_job") ||
    fail "Both simulation jobs were submitted; retry analysis using $campaign/analyze_command.txt"
analysis=${analysis%%;*}
[[ $analysis =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $analysis (inspect squeue before retrying)."
printf 'analysis\t%s\t%s\n' "$analysis" "$results/screen_ns${ns_job}_mc${mc_job}_analysis_${analysis}" >> "$manifest"
printf '%s\n' "$analysis" > "$campaign/analysis_job_id.txt"
echo "Queued analysis $analysis after successful completion of $ns_job and $mc_job"
echo "Submission records and logs: $campaign"
