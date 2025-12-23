#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_JSON" >&2
  exit 2
fi

input_gam="$1"
output_json="$2"

VG_BIN="/gpfs/gibbs/pi/gerstein/hc865/downloads/vg_old"

if [[ ! -f "$input_gam" ]]; then
  echo "ERROR: input not found: $input_gam" >&2
  exit 3
fi

tmp="${output_json}.tmp.$$"
"$VG_BIN" view -aj "$input_gam" > "$tmp"
mv -f "$tmp" "$output_json"
