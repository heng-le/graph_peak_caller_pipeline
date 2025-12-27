#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

nobg="$1"
graph_json="$2"
peaks_intervalcollection="$3"
chrom="$4"
out_interval="$5"
out_bed="$6"
env_path="${7:-}"

mkdir -p "$(dirname "$out_interval")" "$(dirname "$out_bed")"

if [[ -n "${env_path:-}" && -d "$env_path" ]]; then
  conda activate "$env_path"
fi

echo "[flatten] chrom=$chrom"
echo "[flatten] nobg=$nobg"
echo "[flatten] json=$graph_json"
echo "[flatten] peaks=$peaks_intervalcollection"
echo "[flatten] out_interval=$out_interval"
echo "[flatten] out_bed=$out_bed"

graph_peak_caller find_linear_path \
  -g "$nobg" \
  "$graph_json" \
  "$chrom" \
  "$out_interval"

test -f "$out_interval"

if [[ ! -s "$peaks_intervalcollection" ]]; then
  echo "[flatten] INFO: no peaks in $peaks_intervalcollection; writing empty bed for $chrom"
  : > "$out_bed"
  echo "[flatten] OK chrom=$chrom (empty peaks)"
  exit 0
fi

graph_peak_caller peaks_to_linear \
  "$peaks_intervalcollection" \
  "$out_interval" \
  "$chrom" \
  "$out_bed"

test -f "$out_bed"

if [[ ! -s "$out_bed" ]]; then
  echo "[flatten] WARN: empty BED for $chrom (no peaks after flattening?)"
fi

echo "[flatten] OK chrom=$chrom"
