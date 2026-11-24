#!/bin/bash
# Real compilation/smoke check under Ubuntu-24.04 WSL. No cluster access.
set -euo pipefail
setup=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd "$setup/.." && pwd -P)
work=$(mktemp -d /tmp/cpn-N21-real-smoke.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
project="$work/project"
mkdir -p "$project/N21_L72_ubelix_benchmark"
cp "$setup/build_N21_ubelix.sh" "$project/N21_L72_ubelix_benchmark/"
cp -r "$repo/"{include,lib,src} "$project/"
cp "$repo/"{Makefile.am,configure.ac,script_build_code.sh} "$project/"
printf 'generic binary sentinel\n' > "$project/cpn_ns"
before=$(sha256sum "$project/include/macro.h" "$project/cpn_ns")
module() { return 0; }
export -f module
# WSL does not have UBELIX modules/OpenSSL development headers.
ac_cv_header_openssl_md5_h=no bash "$project/N21_L72_ubelix_benchmark/build_N21_ubelix.sh" > "$setup/validation_build.log" 2>&1
[[ $(sha256sum "$project/include/macro.h" "$project/cpn_ns") == "$before" ]]
info=$("$project/cpn_ns_N21" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info"
mkdir "$work/run"
awk '$1=="num_ns_meas" {print $1,3; next} {print}' "$setup/input.template" > "$work/run/input.conf"
cd "$work/run"
"$project/cpn_ns_N21" input.conf > stdout.log 2> stderr.log
[[ $(wc -l < acceptance_rate.dat) == 2 ]]
[[ $(awk '!/^#/ && NF {n++} END {print n}' dati.dat) == 3 ]]
[[ $(awk '!/^#/ && NF {n++} END {print n}' topo.dat) == 33 ]]
head -n1 conf.dat_live_0 | awk '{exit !($2==21 && $3==72 && $4==72)}'
grep -q '^#NS loop wall time:' stdout.log
{
    printf '%s\n' 'PASS: private N=21 build, preserved header/generic binary, real L=72 two-update smoke.'
    cat stdout.log
    printf 'acceptance_rows=2 data_rows=3 topology_rows=33\n'
} | tee "$setup/validation_smoke.log"
