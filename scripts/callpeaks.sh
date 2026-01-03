#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

metrics="$1"
chromosomes_csv="$2"
graph_dir="$3"
exp_prefix="$4"
ctrl_prefix="$5"
out_dir="$6"
genome_size="$7"
read_length="$8"
env_path="$9"
threads="${10}"
done_file="${11}"

mkdir -p "$(dirname "$done_file")" "$out_dir"

unique_reads="$(awk -F'\t' '$1=="unique_reads"{print $2}' "$metrics" | tail -n 1)"
fragment_length="$(awk -F'\t' '$1=="read_length"{print $2}' "$metrics" | tail -n 1)"
skip_tissue="$(awk -F'\t' '$1=="skip_tissue"{print $2}' "$metrics" | tail -n 1)"

if [[ -z "${skip_tissue:-}" ]]; then
  echo "ERROR: skip_tissue missing in $metrics" >&2
  exit 1
fi

if [[ "$skip_tissue" == "True" || "$skip_tissue" == "true" ]]; then
  echo "SKIPPED (skip_tissue=True)" > "$done_file"
  exit 0
fi

if [[ -z "${unique_reads:-}" || -z "${fragment_length:-}" ]]; then
  echo "ERROR: unique_reads/read_length missing in $metrics" >&2
  exit 1
fi

if [[ -n "${env_path:-}" && -d "$env_path" ]]; then
  conda activate "$env_path"
fi

chrom_list="$(echo "$chromosomes_csv" | tr "," "\n" | sed '/^\s*$/d')"

run_one () {
  local chrom="$1"
  local graph="${graph_dir%/}/${chrom}.nobg"
  local sample_json="${exp_prefix}${chrom}.json"
  local control_json="${ctrl_prefix}${chrom}.json"
  local base_name="${out_dir%/}/${chrom}_"

  echo "[callpeaks] chrom=$chrom"
  graph_peak_caller callpeaks \
    -g "$graph" \
    -s "$sample_json" \
    -c "$control_json" \
    -n "$base_name" \
    -f "$fragment_length" \
    -r "$read_length" \
    -p True \
    -u "$unique_reads" \
    -G "$genome_size"
}

export -f run_one
export graph_dir exp_prefix ctrl_prefix out_dir fragment_length read_length unique_reads genome_size

echo "$chrom_list" | xargs -I{} -P "$threads" bash -lc 'run_one "$@"' _ {}

{
  echo "OK"
  echo "unique_reads=$unique_reads"
  echo "fragment_length=$fragment_length"
  echo "read_length=$read_length"
} > "$done_file"
