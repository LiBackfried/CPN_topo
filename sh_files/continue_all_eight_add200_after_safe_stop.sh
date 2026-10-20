#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
marker="$project_dir/out_data/.all_eight_add200_after_safe_stop_started"
test ! -e "$marker"

for spec in \
  "ns_constraint_72_N21_4x500_stoc5000 group_500" \
  "ns_constraint_72_N21_4x2000_stoc5000 group_2000"; do
    read -r output_group config_prefix <<< "$spec"
    for run in 0 1 2 3; do
        output_dir="$project_dir/out_data/$output_group/run_$run"
        config="$project_dir/config_files/ns_constraint_72_N21_add200/${config_prefix}_run_$run"
        test -f "$output_dir/rng_state.dat"
        test -f "$output_dir/conf.dat_live_0"
        (
            cd "$output_dir"
            exec "$project_dir/cpn_ns" "$config" >> stdout.log 2>> stderr.log
        ) &
        echo "$!" > "$output_dir/add200_after_safe_stop_pid"
        echo "Started $output_group/run_$run (PID $!)"
    done
done

date -Is > "$marker"
wait
