#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

chromosomes="$1"
out_dir="$2"
env_path="${3:-}"

mkdir -p "$out_dir"

if [[ -n "$env_path" && -d "$env_path" ]]; then
  conda activate "$env_path"
fi

cd "$out_dir"

graph_peak_caller concatenate_sequence_files \
  "$chromosomes" \
  "all_peaks.fasta"

test -s "all_peaks.fasta"
test -s "all_peaks.intervalcollection"
