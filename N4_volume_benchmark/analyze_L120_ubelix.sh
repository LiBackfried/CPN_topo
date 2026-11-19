#!/bin/bash
# Analyze one four-stream L120 NS job and the three-chain beta=1 MCMC reference.
#SBATCH --job-name=N4_L120_screen
#SBATCH --account=gratis
#SBATCH --partition=epyc2
#SBATCH --qos=job_gratis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=04:00:00
#SBATCH --no-requeue
set -euo pipefail
export LC_ALL=C MPLBACKEND=Agg
fail() { echo "$*" >&2; exit 1; }
[[ $# -ge 2 ]] || fail "Usage: sbatch $0 NS_JOB_ID MCMC_JOB_ID [PREFIX_UPDATES ...]"
[[ ${SLURM_JOB_ID:-} =~ ^[0-9]+$ && ${SLURM_NTASKS:-} == 1 &&
   ${SLURM_CPUS_PER_TASK:-} == 1 ]] || fail 'Submit with sbatch and request one task with one CPU.'
ns_id=$1 mcmc_id=$2
[[ $ns_id =~ ^[0-9]+$ && $mcmc_id =~ ^[0-9]+$ ]] || fail 'Job IDs must be numeric.'
shift 2
prefixes=(30000 60000 90000)
if (( $# )); then prefixes=("$@"); fi
for prefix in "${prefixes[@]}"; do
    [[ $prefix =~ ^[1-9][0-9]{0,8}$ ]] || fail 'Prefix lengths must be positive integers.'
done
repo=$(git -C "${SLURM_SUBMIT_DIR:?Submit from the CPN_topo root.}" rev-parse --show-toplevel)
cd "$repo"
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
ns="$scratch/ns_N4_beta0p7_volume_benchmark/L120/job_$ns_id"
mcmc="$scratch/mcmc_120_N4_beta1p0_3x100k/job_$mcmc_id"
[[ -f "$ns/completed" && $(<"$ns/lattice") == 120 && $(<"$ns/tasks") == 4 ]] || fail "Expected four completed L120 NS streams: $ns"
[[ -f "$mcmc/completed" && $(<"$mcmc/lattice") == 120 && $(<"$mcmc/tasks") == 3 ]] || fail "Expected the completed three-chain L120 MCMC reference: $mcmc"
for run in 0 1 2 3; do
    awk '
        $1 !~ /^#/ && NF {v[$1]=$2; w[$1]=$3}
        END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==0.7 && v["theta"]==0 &&
                    v["num_live_pts"]==50 && v["num_single_site_stoc_upd"]==86400)}
    ' "$ns/run_$run/input.conf" || fail "Unexpected NS settings in $ns/run_$run"
done
for run in 0 1 2; do
    awk '
        $1 !~ /^#/ && NF {v[$1]=$2; w[$1]=$3}
        END {exit !(v["size"]==120 && w["size"]==120 && v["beta"]==1.0 && v["theta"]==0)}
    ' "$mcmc/run_$run/input.conf" || fail "Unexpected MCMC settings in $mcmc/run_$run"
done
module load Python SciPy-bundle matplotlib
python_exec=$(command -v python)
[[ $python_exec == /* ]] || fail 'Python must resolve to an absolute path.'
"$python_exec" -c 'import numpy, scipy, matplotlib'
mkdir -p "$repo/N4_L120_res"
results=$(cd "$repo/N4_L120_res" && pwd -P)
[[ $results == "$repo/N4_L120_res" ]] || fail 'Analysis output must resolve inside repository N4_L120_res.'
output="$results/screen_ns${ns_id}_mc${mcmc_id}_analysis_${SLURM_JOB_ID}"
mkdir "$output"
printf 'kind\tjob_id\tdirectory\nns\t%s\t%s\nmcmc\t%s\t%s\n' "$ns_id" "$ns" "$mcmc_id" "$mcmc" > "$output/inputs.tsv"
printf '%s\n' "${prefixes[@]}" > "$output/requested_prefixes.txt"
echo "Writing L120 screening analysis to $output"
# The scanner includes the deepest shared prefix and follows continuation parents.
srun --export=ALL "$python_exec" N4_volume_benchmark/scan_depth.py "$ns" \
    --updates "${prefixes[@]}" --targets 0.9 0.95 1.0 --bootstrap 200 --seed 20261119 > "$output/depth.csv.tmp"
mv "$output/depth.csv.tmp" "$output/depth.csv"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --output "$output/mcmc_full"
srun --export=ALL "$python_exec" utils/plot_mcmc.py "$mcmc" --burn-in 20000 --output "$output/mcmc_burn20000"
touch "$output/completed"
echo "Saved depth.csv and MCMC diagnostics in $output"
