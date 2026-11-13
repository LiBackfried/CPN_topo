#!/bin/bash
set -euo pipefail
export LC_ALL=C

short=200
long=2000
chains=4

fail() { echo "$*" >&2; exit 1; }

report() {
    local manifest=$1
    local build lattice updates job path short_path task a b cpu elapsed_short elapsed_long
    [[ -r $manifest ]] || fail "Cannot read $manifest"

    while IFS=$'\t' read -r build lattice updates job path; do
        [[ $updates == "$long" ]] || continue
        short_path=$(awk -F '\t' -v build="$build" -v l="$lattice" -v n="$short" \
            '$1 == build && $2 == l && $3 == n { print $5 }' "$manifest")
        if [[ -z $short_path || ! -f "$path/completed" || ! -f "$short_path/completed" ]]; then
            echo "$build L=$lattice: waiting for both pilot jobs to complete (long job $job)." >&2
            continue
        fi
        for ((task=0; task<chains; task++)); do
            a="$short_path/run_$task"
            b="$path/run_$task"
            cpu=$(sed -n '2p' "$a/node.txt")
            if [[ -z $cpu || $cpu != "$(sed -n '2p' "$b/node.txt")" ]]; then
                echo "$build L=$lattice task $task: short and long runs have different CPU models." >&2
                continue
            fi
            elapsed_short=$(awk -F= '$1 == "elapsed_seconds" { print $2 }' "$a/timing.txt")
            elapsed_long=$(awk -F= '$1 == "elapsed_seconds" { print $2 }' "$b/timing.txt")
            awk -v l="$lattice" -v build="$build" -v cpu="$cpu" -v a="$elapsed_short" \
                -v b="$elapsed_long" -v n="$((long-short))" '
                BEGIN {
                    if (a > 0 && b > a) printf "%s\t%s\t%s\t%.9f\n", l, build, cpu, (b-a)/n
                    else printf "%s L=%s: invalid elapsed times (%s, %s)\n", build, l, a, b > "/dev/stderr"
                }'
        done
    done < "$manifest" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2 -k3,3 -k4,4n |
        awk -F '\t' '
            function print_median(    middle, median) {
                if (count == 0) return
                middle = int((count + 1) / 2)
                median = count % 2 ? rates[middle] : (rates[middle] + rates[middle + 1]) / 2
                printf "%s\t%s\t%s\t%d\t%.6f\n", lattice, build, cpu, count, median
            }
            BEGIN { print "L\tbuild\tCPU model\tpaired tasks\tmedian wall seconds/update" }
            $1 != lattice || $2 != build || $3 != cpu {
                print_median()
                lattice = $1; build = $2; cpu = $3; count = 0
            }
            { rates[++count] = $4 }
            END { print_median() }
        '
}

case ${1:-} in
    report)
        [[ $# == 2 ]] || fail "Usage: bash $0 report JOBS_TSV"
        report "$2"
        exit
        ;;
    '') variants=(baseline updated) ;;
    --updated-only) variants=(updated) ;;
    *) fail "Usage: bash $0 [--updated-only] or bash $0 report JOBS_TSV" ;;
esac
(( $# <= 1 )) || fail "Usage: bash $0 [--updated-only]"

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
command -v sbatch >/dev/null || fail 'Run this script on a UBELIX login node.'
baseline=5428e2b
launcher=N4_volume_benchmark/run_ubelix.sh
setup=N4_L22_runs/ns_constraint_22_N4_beta0p7_10x50000_stoc1500
helper="$setup/build_cpn_ns_N4_ubelix.sh"
template="$setup/run_0"
build_files=(src lib include Makefile.am configure.ac script_build_code.sh)
scratch=${NS_SCRATCH:-/scratch/network/users/lb25v444/out_data}
[[ $scratch == /* ]] || fail 'NS_SCRATCH must be an absolute path.'
mkdir -p "$scratch"
campaign=$(mktemp -d "$scratch/cpn_ns_timing.XXXXXX")
manifest="$campaign/jobs.tsv"
printf 'build\tL\tupdates\tjob_id\tjob_dir\n' > "$manifest"
echo "Pilot manifest is $manifest"

for build in "${variants[@]}"; do
    build_dir="$campaign/$build"
    mkdir "$build_dir"
    if [[ $build == baseline ]]; then
        git archive "$baseline" -- "${build_files[@]}" | tar -x -C "$build_dir"
    else
        # Snapshot tracked build inputs from the working tree, including local edits.
        git ls-files -z -- "${build_files[@]}" | tar --null -T - -cf - | tar -x -C "$build_dir"
    fi
    install -D -m 644 "$launcher" "$build_dir/$launcher"
    install -D -m 644 "$helper" "$build_dir/$helper"
    install -D -m 644 "$template" "$build_dir/$template"
    echo "Building $build N=4 executable (log at $build_dir/build.log)"
    (
        cd "$build_dir" &&
        module load foss/2025a &&
        bash script_build_code.sh &&
        bash "$helper"
    ) > "$build_dir/build.log" 2>&1 || fail "$build build failed. See $build_dir/build.log"
done

for build in "${variants[@]}"; do
    volumes=(22 38)
    if [[ $build == updated ]]; then volumes+=(66 90 120); fi
    cd "$campaign/$build"
    for lattice in "${volumes[@]}"; do
        for updates in "$short" "$long"; do
            # A task gets the same seed at both lengths and with both builds.
            seed_base=$((70600 + 32 * lattice))
            job=$(env -u NS_STOC -u NS_INIT_SWEEPS -u NS_INIT_SPACING -u NS_EXECUTABLE \
                NS_SCRATCH="$campaign" NS_SEED_BASE="$seed_base" \
                sbatch --parsable --export=ALL --ntasks="$chains" --cpus-per-task=1 \
                --time=00:30:00 --job-name="ns_${build}_L${lattice}_${updates}" \
                "$launcher" "$lattice" "$updates") || fail "Submission failed. See $manifest for jobs already submitted."
            job=${job%%;*}
            [[ $job =~ ^[0-9]+$ ]] || fail "Unexpected sbatch output: $job"
            path="$campaign/ns_N4_beta0p7_volume_benchmark/L$lattice/job_$job"
            printf '%s\t%s\t%s\t%s\t%s\n' "$build" "$lattice" "$updates" "$job" "$path" >> "$manifest"
            echo "Submitted $build L=$lattice, $updates updates as job $job"
        done
    done
done

printf 'After the jobs finish, run:\n  bash %q report %q\n' "$repo/N4_volume_benchmark/time_ubelix.sh" "$manifest"
