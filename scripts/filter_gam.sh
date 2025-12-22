#!/usr/bin/env bash
#SBATCH --partition=day
#SBATCH --mem=20G
#SBATCH --time=12:00:00
#SBATCH -c 4
#SBATCH --account=gerstein
#SBATCH --job-name=gpc_filter

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 INPUT_GAM OUTPUT_GAM" >&2
  exit 2
fi

input_gam=$1
output_gam=$2

FILTER_COMMAND="/gpfs/gibbs/pi/gerstein/hc865/downloads/vg_old filter -r 0.95 -s 2.0 -q 60 -fu \"$input_gam\" > \"$output_gam\""


if [ -z "$FILTER_COMMAND" ]; then
  echo "ERROR: set FILTER_COMMAND in scripts/filter_gam.sh" >&2
  echo "Example: FILTER_COMMAND='vg filter -r 0.9 \"$input_gam\" > \"$output_gam\"'" >&2
  exit 2
fi

eval "$FILTER_COMMAND"
