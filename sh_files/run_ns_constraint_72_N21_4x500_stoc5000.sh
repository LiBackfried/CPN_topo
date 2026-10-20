#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
run_group="ns_constraint_72_N21_4x500_stoc5000"

if (( $# )); then
    runs=("$@")
else
    runs=(0 1 2 3)
fi

for run in "${runs[@]}"; do
    output_dir="$project_dir/out_data/$run_group/run_$run"
    config="$project_dir/config_files/$run_group/run_$run"
    mkdir -p "$output_dir"
    (
        cd "$output_dir"
        exec "$project_dir/cpn_ns" "$config" > stdout.log 2> stderr.log
    ) &
    echo "$!" > "$output_dir/pid"
    echo "Started run_$run (PID $!)"
done

wait
