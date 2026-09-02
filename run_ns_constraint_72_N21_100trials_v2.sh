#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$project_dir/out_data/ns_constraint_72_N21_100trials_2"

mkdir -p "$output_dir"
cd "$output_dir"

exec "$project_dir/cpn_ns" "$project_dir/config_files/ns_constraint_72_N21_100trials_2"
