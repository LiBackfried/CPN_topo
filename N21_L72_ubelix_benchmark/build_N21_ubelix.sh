#!/bin/bash
# Run with bash on UBELIX. Build privately; preserve every existing model build.
set -euo pipefail
export LC_ALL=C
case ${1:-ns} in
    ns) target=cpn_ns ;;
    mcmc) target=cpn ;;
    *) echo "Usage: bash $0 [ns|mcmc]" >&2; exit 1 ;;
esac
[[ $# -le 1 ]]
binary="${target}_N21"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# The serial code needs GCC, not foss's MPI/libevent stack (which needs OpenSSL/3).
# Purging here affects this child shell, not the submitting shell or running jobs.
module purge
module load GCCcore/14.2.0 OpenSSL/1.1
work=$(mktemp -d "${TMPDIR:-/tmp}/cpn-N21-build.XXXXXXXX")
# Leave the temporary directory before removing it. Modules are local to this Bash process.
trap 'cd / && rm -rf -- "$work"' EXIT
mkdir "$work/include" "$work/lib" "$work/src"
cp "$repo/"{Makefile.am,configure.ac,script_build_code.sh} "$work/"
cp "$repo/include/"*.h "$work/include/"
cp "$repo/lib/"*.c "$work/lib/"
cp "$repo/src/"*.c "$work/src/"
cd "$work"
# Normalize copied Windows line endings, leaving the checkout untouched.
sed -i 's/\r$//' Makefile.am configure.ac script_build_code.sh include/*.h lib/*.c src/*.c
sed -i -E 's/^#define N [0-9]+[[:space:]]*$/#define N 21/' include/macro.h
grep -Fxq '#define N 21' include/macro.h
sha256sum Makefile.am configure.ac include/*.h lib/*.c src/*.c > source_sha256.txt
# Same monotonic loop-boundary probe used in the local timing campaign.
if [[ $target == cpn_ns ]]; then
    awk '
    /^[[:space:]]*start_time=clock\(\);/ {
        starts++; print
        print "\tstruct timespec wall_start, wall_finish;"
        print "\tclock_gettime(CLOCK_MONOTONIC, &wall_start);"
        next
    }
    /^[[:space:]]*finish_time=clock\(\);/ {
        finishes++
        print "\tclock_gettime(CLOCK_MONOTONIC, &wall_finish);"
        print
        print "\tfprintf(stdout, \"#NS loop wall time: %.9f s\\n\","
        print "\t        (double)(wall_finish.tv_sec - wall_start.tv_sec) +"
        print "\t        1e-9 * (double)(wall_finish.tv_nsec - wall_start.tv_nsec));"
        next
    }
    {print}
    END {if (starts != 1 || finishes != 1) exit 1}
' src/cpn_ns.c > src/cpn_ns.instrumented
    mv src/cpn_ns.instrumented src/cpn_ns.c
fi
log="$repo/$binary.build.log"
{
    bash script_build_code.sh
    ./configure CC=gcc CFLAGS=-O3
    make -j2 "$target"
} > "$log" 2>&1 || { tail -n 60 "$log" >&2; exit 1; }
info=$("./$target" 2>&1 || true)
grep -Fxq 'Compiled with N = 21' <<< "$info"
if [[ $target == cpn_ns ]]; then grep -aFq '#NS loop wall time:' "$target"; fi
{
    date -u '+Built at %Y-%m-%dT%H:%M:%SZ'
    printf 'Compile-time N: 21\nBuild target: %s\n' "$target"
    if [[ $target == cpn_ns ]]; then printf 'Timing probe: CLOCK_MONOTONIC\n'; fi
    if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'Checkout revision: '; git -C "$repo" rev-parse HEAD
        git -C "$repo" status --short -- src lib include Makefile.am configure.ac
    else
        printf 'Checkout revision: unavailable (source copy without Git metadata)\n'
    fi
    gcc --version
    module list 2>&1
    cat config.h
    cat source_sha256.txt
    sha256sum "src/$target.c"
    printf '%s\n' "$info"
} > "$repo/$binary.build_info.txt"
install -m 755 "$target" "$repo/$binary.new"
mv -f "$repo/$binary.new" "$repo/$binary"
sha256sum "$repo/$binary" | tee "$repo/$binary.sha256"
echo "Built $repo/$binary; existing header, objects and other executables preserved."
