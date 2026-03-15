#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

metrics="$1"
chromosomes_csv="$2"
graph_dir="$3"
out_dir="$4"
env_path="$5"
threads="$6"
done_file="$7"

mkdir -p "$(dirname "$done_file")" "$out_dir"

read_length="$(awk -F'\t' '$1=="read_length"{print $2}' "$metrics" | tail -n 1)"
fragment_length="$(awk -F'\t' '$1=="fragment_length"{print $2}' "$metrics" | tail -n 1)"
skip_tissue="$(awk -F'\t' '$1=="skip_tissue"{print $2}' "$metrics" | tail -n 1)"

if [[ -z "${skip_tissue:-}" ]]; then
  echo "ERROR: skip_tissue missing in $metrics" >&2
  exit 1
fi

if [[ "$skip_tissue" == "True" || "$skip_tissue" == "true" ]]; then
  echo "SKIPPED (skip_tissue=True)" > "$done_file"
  exit 0
fi

if [[ -z "${read_length:-}" || -z "${fragment_length:-}" || "$fragment_length" == "NA" ]]; then
  echo "ERROR: read_length/fragment_length missing or fragment_length=NA in $metrics" >&2
  exit 1
fi

if [[ -n "${env_path:-}" && -d "$env_path" ]]; then
  conda activate "$env_path"
fi

cd "$out_dir"

chrom_list="$(echo "$chromosomes_csv" | tr "," "\n" | sed '/^\s*$/d')"

run_one () {
  local chrom="$1"
  echo "[pvalues] chrom=$chrom"
  graph_peak_caller callpeaks_whole_genome_from_p_values \
    -d "${graph_dir%/}/" \
    -n "" \
    -f "$fragment_length" \
    -r "$read_length" \
    "$chrom"
}

export -f run_one
export graph_dir fragment_length read_length

echo "$chrom_list" | xargs -I{} -P "$threads" bash -lc 'run_one "$@"' _ {}

{
  echo "OK"
  echo "fragment_length=$fragment_length"
  echo "read_length=$read_length"
} > "$done_file"
