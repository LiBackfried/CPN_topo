#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
output_group="ns_constraint_72_N21_4x500_stoc5000"
config_group="ns_constraint_72_N21_4x500_stoc5000_continue_to_2000"

for run in 0 1 2 3; do
    output_dir="$project_dir/out_data/$output_group/run_$run"
    config="$project_dir/config_files/$config_group/run_$run"
    test -f "$output_dir/rng_state.dat"
    test -f "$output_dir/conf.dat_live_0"
    (
        cd "$output_dir"
        exec "$project_dir/cpn_ns" "$config" >> stdout.log 2>> stderr.log
    ) &
    echo "$!" > "$output_dir/continue_pid"
    echo "Continued run_$run (PID $!)"
done

wait
