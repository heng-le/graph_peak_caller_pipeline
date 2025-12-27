#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_GAM" >&2
  exit 2
fi

input_gam="$1"
output_gam="$2"

: "${VG_BIN:?ERROR: VG_BIN not set (export VG_BIN=/path/to/vg executable)}"

if [[ ! -f "$input_gam" ]]; then
  echo "ERROR: input not found: $input_gam" >&2
  exit 3
fi

if [[ ! -x "$VG_BIN" ]]; then
  echo "ERROR: vg executable not found or not executable: $VG_BIN" >&2
  exit 4
fi

tmp="${output_gam}.tmp.$$"
"$VG_BIN" filter -r 0.95 -s 2.0 -q 60 -fu "$input_gam" > "$tmp"
mv -f "$tmp" "$output_gam"
