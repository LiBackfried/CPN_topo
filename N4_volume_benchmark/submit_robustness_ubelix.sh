#!/bin/bash
# Submission helper: bash this file; it submits the analysis worker with sbatch.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# -le 1 ]] || fail "Usage: bash $0 [all|90|120]"
case "${1:-all}" in
    all) volumes=(90 120) ;;
    90|120) volumes=("$1") ;;
    *) fail 'Choose all, 90 or 120.' ;;
esac
repo=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$repo"
worker="$repo/N4_volume_benchmark/robustness_L90_L120_ubelix.sh"
[[ -f "$worker" && -f N4_volume_benchmark/check_ensemble_robustness.py ]] || fail 'Sync the analysis scripts first.'
command -v sbatch >/dev/null || fail 'Run this submission helper on UBELIX.'
for lattice in "${volumes[@]}"; do
    mkdir -p "$repo/N4_L${lattice}_res"
    results=$(cd "$repo/N4_L${lattice}_res" && pwd -P)
    [[ $results == "$repo/N4_L${lattice}_res" ]] || fail 'Result folder must resolve inside the repository.'
    records=$(mktemp -d "$results/robustness_submit.XXXXXX")
    cp "$worker" "$records/worker.sh"
    printf 'Submitted_UTC\tL\tjob_id\n' > "$records/submitted.tsv"
    # With --parsable a federated Slurm may append ;cluster. Keep the numeric ID.
    submission=$(sbatch --parsable --chdir="$repo" --job-name="N4L${lattice}_robustness" \
        --output="$records/slurm-%j.out" --error="$records/slurm-%j.err" "$records/worker.sh" "$lattice")
    id=${submission%%;*}
    [[ $id =~ ^[0-9]+$ ]] || fail "Unexpected sbatch response: $submission (records: $records)"
    printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$lattice" "$id" >> "$records/submitted.tsv"
    printf 'Submitted L%s robustness job %s\nLogs and submission record: %s\nResults: %s/robustness_steps12_%s\n' \
        "$lattice" "$id" "$records" "$results" "$id"
done
