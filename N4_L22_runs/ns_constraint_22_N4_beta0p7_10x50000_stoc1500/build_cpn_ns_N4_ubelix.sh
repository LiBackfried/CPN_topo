#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/../.." && pwd)"
cd "$project_dir"

module load foss/2025a
module load OpenSSL/1.1

header="include/macro.h"
header_backup="$(mktemp)"
binary_backup=""
cp -p "$header" "$header_backup"

if [[ -e cpn_ns ]]; then
    binary_backup="$(mktemp)"
    cp -p cpn_ns "$binary_backup"
fi

restore_project_state() {
    cp -p "$header_backup" "$header"
    # Keep the restored N value newer than the N=4 object files so that a
    # subsequent normal make cannot accidentally reuse those objects.
    touch "$header"
    rm -f "$header_backup"

    if [[ -n "$binary_backup" ]]; then
        cp -p "$binary_backup" cpn_ns
        rm -f "$binary_backup"
    else
        rm -f cpn_ns
    fi

    module purge || true
}
trap restore_project_state EXIT

sed -E 's/^#define N [0-9]+$/#define N 4/' "$header_backup" > "$header"
grep -q '^#define N 4$' "$header" || {
    echo "Could not set N=4 in $header" >&2
    exit 1
}

./configure CFLAGS='-O3'
make -B cpn_ns
cp -p cpn_ns cpn_ns_N4

compile_info="$(./cpn_ns_N4 2>&1 || true)"
grep -q 'Compiled with N = 4' <<< "$compile_info" || {
    echo "Built executable did not report N=4." >&2
    exit 1
}

echo "Created $project_dir/cpn_ns_N4"

