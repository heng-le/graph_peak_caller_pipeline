#!/usr/bin/env bash
set -euo pipefail

in_json="$1"
out_txt="$2"

mkdir -p "$(dirname "$out_txt")"

count="$(
  { grep -aoE '"sequence"[[:space:]]*:[[:space:]]*"[ACGTNacgtn]{20,}"' "$in_json" || true; } \
    | awk -F'"' '{print $4}' \
    | LC_ALL=C sort -u \
    | wc -l
)"

echo "$count" > "$out_txt"
