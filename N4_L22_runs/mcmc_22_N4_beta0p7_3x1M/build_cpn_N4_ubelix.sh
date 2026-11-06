#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/../.." && pwd)"

module load foss/2025a
module load OpenSSL/1.1

# Compile in a private source copy. Publish the executable after verification.
build_dir="$(mktemp -d "$project_dir/.cpn_N4_build.XXXXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
cd "$build_dir"

cp "$project_dir"/{configure.ac,Makefile.am,script_build_code.sh} .
mkdir include lib src
cp "$project_dir"/include/*.h include/
cp "$project_dir"/lib/*.c lib/
cp "$project_dir"/src/*.c src/
sed -i -E 's/^#define N [0-9]+$/#define N 4/' include/macro.h

bash script_build_code.sh
./configure CFLAGS='-O3'
make cpn

compile_info="$(./cpn 2>&1 || true)"
if ! grep -Fxq 'Compiled with N = 4' <<< "$compile_info"; then
    echo "Built cpn did not report N=4." >&2
    exit 1
fi

mv -fT cpn "$project_dir/cpn_N4"
echo "Created $project_dir/cpn_N4"
