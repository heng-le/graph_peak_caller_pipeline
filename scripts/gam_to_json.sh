#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_JSON VG_BIN" >&2
  exit 2
fi

input_gam="$1"
output_json="$2"
VG_BIN="$3"

if [[ ! -f "$input_gam" ]]; then
  echo "ERROR: input not found: $input_gam" >&2
  exit 3
fi

if [[ ! -x "$VG_BIN" ]]; then
  echo "ERROR: vg executable not found or not executable: $VG_BIN" >&2
  exit 4
fi

mkdir -p "$(dirname "$output_json")"

tmp="${output_json}.tmp.$$"
"$VG_BIN" view -aj "$input_gam" > "$tmp"
mv -f "$tmp" "$output_json"
