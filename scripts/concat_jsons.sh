#!/usr/bin/env bash
set -euo pipefail

out="$1"
shift

mkdir -p "$(dirname "$out")"

: > "$out"
for f in "$@"; do
  cat "$f" >> "$out"
done
