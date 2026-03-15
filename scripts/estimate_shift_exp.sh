#!/usr/bin/env bash
set -euo pipefail
module purge
module load miniconda

chromosomes="$1"   
graph_dir="$2"     
prefix="$3"        
env_dir="$4"       
out_log="$5"      
out_fragmentlen="$6"   
out_skip="$7"      

mkdir -p "$(dirname "$out_log")"
mkdir -p "$(dirname "$out_fragmentlen")"
mkdir -p "$(dirname "$out_skip")"

if [[ -n "${env_dir}" && -d "${env_dir}" ]]; then
  conda activate "${env_dir}"
fi

set +e
graph_peak_caller estimate_shift \
  "${chromosomes}" \
  "${graph_dir}" \
  "${prefix}" \
  5 100 \
  &> "${out_log}"
rc=$?
set -e

# Parse output for "Found shift: N"
if grep -q "Found shift:" "${out_log}"; then
  shift_val="$(grep "Found shift:" "${out_log}" | tail -n 1 | awk -F'Found shift: ' '{print $2}' | awk '{print $1}')"
  echo "${shift_val}" > "${out_fragmentlen}"
  echo "False" > "${out_skip}"
else
  echo "NA" > "${out_fragmentlen}"
  echo "True" > "${out_skip}"
fi

echo "estimate_shift_exit_code=${rc}" >> "${out_log}"

exit 0
