#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "Usage: $0 INPUT_COMBINED_JSON CHROMOSOMES_CSV GRAPH_DIR CONDA_ENV" >&2
  exit 2
fi

input_json="$1"
chrom_csv="$2"
graph_dir="$3"
conda_env="$4"

[[ -f "$input_json" ]] || { echo "ERROR: input not found: $input_json" >&2; exit 3; }

workdir="$(dirname "$input_json")"
base="$(basename "$input_json")"
prefix="${base%.json}"

if command -v module >/dev/null 2>&1; then
  module load miniconda >/dev/null 2>&1 || true
fi

command -v conda >/dev/null 2>&1 || { echo "ERROR: conda not found" >&2; exit 4; }
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$conda_env"

cd "$workdir"

graph_peak_caller split_vg_json_reads_into_chromosomes \
  "$chrom_csv" \
  "$base" \
  "$graph_dir"

IFS=',' read -r -a chroms <<< "$chrom_csv"
for c in "${chroms[@]}"; do
  out="${prefix}_${c}.json"
  [[ -s "$out" ]] || { echo "ERROR: missing/empty output: $workdir/$out" >&2; exit 5; }
done
