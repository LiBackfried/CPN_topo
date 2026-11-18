#!/bin/bash
# Submission driver/report: run with bash on a UBELIX login node.
set -euo pipefail
export LC_ALL=C
fail() { echo "$*" >&2; exit 1; }

report() {
    local manifest=$1 campaign kind l beta stoc steps seeds job path short short_path task a b cpu ca cb ta tb seed_a seed_b
    local incomplete=0
    [[ -r $manifest ]] || fail "Cannot read $manifest"
    campaign=$(cd "$(dirname "$manifest")" && pwd -P)
    [[ $(head -n1 "$manifest") == $'kind\tL\tbeta\tproposals\tsteps\tseed_base\tjob_id\tjob_directory' ]] || fail 'Unexpected manifest header.'
    printf 'kind\tL\tbeta\tproposals\tCPU\ttask\tseconds_per_step\tmax_rss_kib\n' > "$campaign/paired_rates.tsv.tmp"
    while IFS=$'\t' read -r kind l beta stoc steps seeds job path; do
        case $kind/$steps in ns/2000) short=200 ;; mcmc/20000) short=2000 ;; *) continue ;; esac
        short_path=$(awk -F '\t' -v k="$kind" -v l="$l" -v b="$beta" -v p="$stoc" -v n="$short" -v s="$seeds" \
            '$1==k && $2==l && $3==b && $4==p && $5==n && $6==s {print $8}' "$manifest")
        if [[ -z $short_path || ! -f "$path/completed" || ! -f "$short_path/completed" ]]; then
            echo "Waiting for both completed jobs: $kind L$l proposals=$stoc (long job $job)" >&2
            incomplete=1; continue
        fi
        for task in 0 1 2 3; do
            a="$short_path/run_$task" b="$path/run_$task"
            ca=$(sed -n '2p' "$a/node.txt"); cb=$(sed -n '2p' "$b/node.txt")
            seed_a=$(awk '$1=="rng_seed" {print $2}' "$a/input.conf")
            seed_b=$(awk '$1=="rng_seed" {print $2}' "$b/input.conf")
            if [[ -z $ca || $ca != "$cb" || $seed_a != "$seed_b" || $seed_a != "$((seeds+task))" ]]; then
                echo "Unmatched CPU model or seed: $kind L$l proposals=$stoc task=$task" >&2
                incomplete=1; continue
            fi
            ta=$(awk -F= '$1=="elapsed_seconds" {print $2}' "$a/timing.txt")
            tb=$(awk -F= '$1=="elapsed_seconds" {print $2}' "$b/timing.txt")
            cpu=$ca
            if ! awk -v k="$kind" -v l="$l" -v b="$beta" -v p="$stoc" -v cpu="$cpu" -v task="$task" \
                -v a="$ta" -v z="$tb" -v n="$((steps-short))" \
                -v rss="$(awk -F= '$1=="max_rss_kib" {print $2}' "$b/timing.txt")" '
                BEGIN {
                    if (a !~ /^[0-9]+([.][0-9]+)?$/ || z !~ /^[0-9]+([.][0-9]+)?$/ || a<=0 || z<=a) exit 1
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%.9f\t%s\n",k,l,b,p,cpu,task,(z-a)/n,rss
                }' >> "$campaign/paired_rates.tsv.tmp"; then
                echo "Invalid timing pair: $kind L$l proposals=$stoc task=$task" >&2
                incomplete=1
            fi
        done
    done < "$manifest"
    mv "$campaign/paired_rates.tsv.tmp" "$campaign/paired_rates.tsv"
    {
        printf 'kind\tL\tbeta\tproposals\tCPU\tpaired_tasks\tmedian_seconds_per_step\tmax_rss_kib\tprojected_steps\thours_per_chain\ttotal_CPU_hours\n'
        tail -n +2 "$campaign/paired_rates.tsv" | sort -t $'\t' -k1,1 -k2,2n -k3,3n -k4,4n -k5,5 -k7,7n |
            awk -F '\t' '
                function emit(    m,r,n,chains) {
                    if (!count) return
                    m=int((count+1)/2); r=(count%2 ? rates[m] : (rates[m]+rates[m+1])/2)
                    n=(kind=="mcmc" ? 1000000 : (l==90 ? 210000 : 370000)); chains=(kind=="mcmc" ? 3 : 12)
                    printf "%s\t%s\t%s\t%s\t%s\t%d\t%.9f\t%d\t%d\t%.3f\t%.3f\n",kind,l,beta,p,cpu,count,r,rss,n,r*n/3600,chains*r*n/3600
                }
                $1!=kind || $2!=l || $3!=beta || $4!=p || $5!=cpu {
                    emit(); kind=$1; l=$2; beta=$3; p=$4; cpu=$5; count=0; rss=0
                }
                {rates[++count]=$7; if ($8>rss) rss=$8}
                END {emit()}
            '
    } | tee "$campaign/report.tsv"
    echo 'Projections exclude initialization and assume early-depth rates persist; compare CPU groups separately.' >&2
    (( ! incomplete ))
}

if [[ ${1:-} == report ]]; then
    [[ $# == 2 ]] || fail "Usage: bash $0 report JOBS_TSV"
    report "$2"
    exit
fi
[[ $# -le 1 ]] || fail "Usage: bash $0 [90|120|all] or bash $0 report JOBS_TSV"
case ${1:-90} in 90) volumes=(90) ;; 120) volumes=(120) ;; all) volumes=(90 120) ;; *) fail 'Choose 90, 120 or all.' ;; esac
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
command -v sbatch >/dev/null || fail 'Run this submission driver on UBELIX.'
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be absolute.'
ns_exe=${NS_EXECUTABLE:-$repo/cpn_ns_N4}
mc_exe=${MCMC_EXECUTABLE:-$repo/cpn_N4}
module load OpenSSL/1.1
for executable in "$ns_exe" "$mc_exe"; do
    [[ $executable == /* && -x $executable ]] || fail 'Build both N=4 executables first (see L90_L120_BENCHMARK.md).'
    info=$("$executable" 2>&1 || true)
    grep -Fxq 'Compiled with N = 4' <<< "$info" || fail "Expected N=4: $executable"
done
mkdir -p "$scratch"
campaign=$(mktemp -d "$scratch/cpn_N4_L90_L120_timing.XXXXXX")
mkdir "$campaign/bin" "$campaign/templates"
cp "$ns_exe" "$campaign/bin/cpn_ns_N4"
cp "$mc_exe" "$campaign/bin/cpn_N4"
cp "$repo/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0" "$campaign/templates/ns.conf"
cp "$repo/N4_volume_benchmark/mcmc_90_N4_beta0p95_3x100k/run_0.conf" "$campaign/templates/mcmc.conf"
cp "$repo/N4_volume_benchmark/run_timing_L90_L120_ubelix.sh" "$campaign/"
cp "$repo/N4_volume_benchmark/benchmark_L90_L120_ubelix.sh" "$campaign/"
sha256sum "$campaign/bin/"* > "$campaign/executable_sha256.txt"
manifest="$campaign/jobs.tsv"
printf 'kind\tL\tbeta\tproposals\tsteps\tseed_base\tjob_id\tjob_directory\n' > "$manifest"
# Remove inherited Slurm submission options; every job declares its own resources.
for name in ${!SBATCH_@}; do unset "$name"; done
echo "Timing campaign: $campaign"
for L in "${volumes[@]}"; do
    for kind in ns mcmc; do
        if [[ $kind == ns ]]; then
            beta=0.7 proposals=("$((3*L*L))" "$((6*L*L))") lengths=(200 2000)
            seed_base=$((809000+32*L))
        else
            case $L in 90) beta=0.95 ;; 120) beta=1.0 ;; esac
            proposals=(0) lengths=(2000 20000) seed_base=$((909000+32*L))
        fi
        for stoc in "${proposals[@]}"; do
            for steps in "${lengths[@]}"; do
                job=$(sbatch --parsable --export=ALL --chdir="$campaign" --ntasks=4 --cpus-per-task=1 \
                    --time=00:45:00 --job-name="${kind}_L${L}_p${stoc}_${steps}" \
                    --output="$campaign/slurm_%j.out" "$campaign/run_timing_L90_L120_ubelix.sh" \
                    "$kind" "$L" "$steps" "$stoc" "$seed_base" "$campaign") ||
                    fail "Submission failed; already submitted jobs are listed in $manifest"
                job=${job%%;*}
                [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $job (check squeue before retrying)."
                path="$campaign/${kind}_L${L}_stoc${stoc}_${steps}/job_$job"
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$L" "$beta" "$stoc" "$steps" "$seed_base" "$job" "$path" >> "$manifest"
                echo "Submitted $job: $kind L=$L beta=$beta steps=$steps proposals=$stoc (four chains)"
            done
        done
    done
done
printf 'After completion:\n  bash %q report %q\n' "$campaign/benchmark_L90_L120_ubelix.sh" "$manifest" | tee "$campaign/report_command.txt"
