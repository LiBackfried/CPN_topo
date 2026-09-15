#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
run_group="ns_constraint_72_N21_4x2000_stoc5000"

for run in 0 1 2 3; do
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
