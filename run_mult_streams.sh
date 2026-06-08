#!/usr/bin/env bash

###set -e   ### "warnings (and errors) can be ignored " - A.A., 2024

N_RUNS=8
BASE_SEED=12345
OUTDIR="out_data_multrun_"

echo "Starting $N_RUNS nested sampling runs..."

pids=()

for i in $(seq 2 $N_RUNS); do
    mkdir -p "$OUTDIR${i}"
    echo "Launching run $i"

    ./ns \
        --seed "$SEED" \
        --out "$OUTFILE" \
        > "$LOGFILE" 2>&1 &

    pids+=($!)
done

echo "Waiting for all runs to finish..."

for pid in "${pids[@]}"; do
    wait "$pid"
done

echo "All runs completed."