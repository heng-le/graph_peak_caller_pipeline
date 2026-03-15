#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_JSON VG_BIN OUTPUT_READ_LENGTH" >&2
  exit 2
fi

input_gam="$1"
output_json="$2"
VG_BIN="$3"
output_read_length="$4"

if [[ ! -f "$input_gam" ]]; then
  echo "ERROR: input not found: $input_gam" >&2
  exit 3
fi

if [[ ! -x "$VG_BIN" ]]; then
  echo "ERROR: vg executable not found or not executable: $VG_BIN" >&2
  exit 4
fi

mkdir -p "$(dirname "$output_json")"
mkdir -p "$(dirname "$output_read_length")"

tmp="${output_json}.tmp.$$"
"$VG_BIN" view -aj "$input_gam" > "$tmp"
python3 scripts/infer_read_length.py "$tmp" "$output_read_length"
mv -f "$tmp" "$output_json"
