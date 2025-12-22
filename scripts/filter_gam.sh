#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_GAM" >&2
  exit 2
fi

input_gam="$1"
output_gam="$2"

VG_BIN="/gpfs/gibbs/pi/gerstein/hc865/downloads/vg_old"

if [[ ! -f "$input_gam" ]]; then
  echo "ERROR: input not found: $input_gam" >&2
  exit 3
fi

tmp="${output_gam}.tmp.$$"
"$VG_BIN" filter -r 0.95 -s 2.0 -q 60 -fu "$input_gam" > "$tmp"
mv -f "$tmp" "$output_gam"
