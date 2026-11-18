#!/bin/bash
# Run under Ubuntu-24.04 WSL. Build privately; never change the repository N.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
output="$repo/N4_L66_res/local_benchmark_20261118"
mkdir -p "$output"
work=$(mktemp -d /tmp/cpn-L66.XXXXXXXX)
printf '%s\n' "$work" > "$output/work_directory.txt"
mkdir "$work/source"
cp "$repo"/{configure.ac,Makefile.am,script_build_code.sh} "$work/source/"
cp -r "$repo"/{include,lib,src} "$work/source/"
cd "$work/source"
sed -i -E 's/^#define N [0-9]+\r?$/#define N 4/' include/macro.h
{
    bash script_build_code.sh
    ac_cv_header_openssl_md5_h=no ./configure CFLAGS=-O3
    make -j2 cpn cpn_ns
} > "$output/build.log" 2>&1
for exe in cpn cpn_ns; do
    info=$("$work/source/$exe" 2>&1 || true)
    grep -Fxq 'Compiled with N = 4' <<< "$info"
done
awk -F ': ' '/^model name/ {print $2; exit}' /proc/cpuinfo > "$output/cpu.txt"
printf 'kind,proposals,seed,steps,elapsed_seconds,max_rss_kib\n' > "$output/timings.csv"
# Matched short/long pairs subtract initialization; two independent seeds.
for seed in 806601 806602; do
    for stoc in 13068 26136; do
        for steps in 100 1100; do
            run="$work/ns_${stoc}_${seed}_${steps}"
            mkdir "$run"
            awk -v stoc="$stoc" -v seed="$seed" -v meas="$((steps+1))" '
                $1=="size" {print $1,66,66; next}
                $1=="rng_seed" {print $1,seed; next}
                $1=="num_ns_meas" {print $1,meas; next}
                $1=="num_single_site_stoc_upd" {print $1,stoc; next}
                {print}
            ' "$repo/N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500/run_0" > "$run/input.conf"
            (cd "$run"; /usr/bin/time -f '%e,%M' -o timing.csv "$work/source/cpn_ns" input.conf > stdout.log)
            [[ $(wc -l < "$run/acceptance_rate.dat") == "$steps" ]]
            printf 'ns,%s,%s,%s,%s\n' "$stoc" "$seed" "$steps" "$(cat "$run/timing.csv")" >> "$output/timings.csv"
        done
    done
    for steps in 1000 11000; do
        run="$work/mcmc_${seed}_${steps}"
        mkdir "$run"
        awk -v seed="$seed" -v steps="$steps" '
            $1=="rng_seed" {print $1,seed; next}
            $1=="num_MC_step" {print $1,steps; next}
            {print}
        ' "$repo/N4_volume_benchmark/mcmc_66_N4_beta0p9_3x100k/run_0.conf" > "$run/input.conf"
        (cd "$run"; /usr/bin/time -f '%e,%M' -o timing.csv "$work/source/cpn" input.conf > stdout.log)
        rows=$(awk '!/^#/ && NF {n++} END {print n+0}' "$run/dati.dat")
        [[ $rows == "$((steps/10))" ]]
        printf 'mcmc,0,%s,%s,%s\n' "$seed" "$steps" "$(cat "$run/timing.csv")" >> "$output/timings.csv"
    done
done
echo "Saved timing results in $output; private build/checkpoints retained in $work"
