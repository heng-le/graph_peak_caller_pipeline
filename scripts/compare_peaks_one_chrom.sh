#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

peaks_ic="$1"        # chrN_max_paths.intervalcollection (graph peaks)
bed="$2"             # chrN.bed (flattened peaks)
interval="$3"        # chrN.interval (linear path interval)
chrom="$4"           # chrN
out_missing="$5"     # desired output: chrN_missing.intervalcollection
env_path="${6:-}"    # optional conda env path

mkdir -p "$(dirname "$out_missing")"

if [[ -n "${env_path:-}" && -d "$env_path" ]]; then
  conda activate "$env_path"
fi

# Always produce an output file, even for empty inputs
# If peaks intervalcollection is empty or missing → no missing peaks to report
if [[ ! -f "$peaks_ic" || ! -s "$peaks_ic" ]]; then
  : > "$out_missing"
  echo "[compare_peaks] WARN: empty/missing peaks_ic for $chrom; wrote empty $out_missing" >&2
  exit 0
fi

# These should exist if flattening ran successfully; treat as hard errors if missing
if [[ ! -f "$bed" ]]; then
  echo "[compare_peaks] ERROR: bed not found: $bed" >&2
  exit 2
fi

if [[ ! -f "$interval" ]]; then
  echo "[compare_peaks] ERROR: interval not found: $interval" >&2
  exit 3
fi

workdir="$(dirname "$out_missing")"
mkdir -p "$workdir"
cd "$workdir"

# Avoid stale results
rm -f "${chrom}_missing.intervalcollection"

echo "[compare_peaks] chrom=$chrom"
echo "[compare_peaks] peaks_ic=$peaks_ic"
echo "[compare_peaks] bed=$bed"
echo "[compare_peaks] interval=$interval"
echo "[compare_peaks] out_missing=$out_missing"

graph_peak_caller compare_peaks "$peaks_ic" "$bed" "$interval" "$chrom"

if [[ -f "${chrom}_missing.intervalcollection" ]]; then
  if [[ "$out_missing" != "${workdir}/${chrom}_missing.intervalcollection" ]]; then
    mv -f "${chrom}_missing.intervalcollection" "$out_missing"
  fi
fi

if [[ ! -f "$out_missing" ]]; then
  : > "$out_missing"
fi

echo "[compare_peaks] OK chrom=$chrom"
