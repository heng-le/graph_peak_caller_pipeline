#!/bin/bash
#SBATCH --job-name=snakemake_job
#SBATCH --partition=pi_gerstein
#SBATCH --account=gerstein
#SBATCH --time=7-00:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=10G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=heng-le.chen@yale.edu
#SBATCH --output=logs/snakejob-%j.txt

set -euo pipefail

module purge
module load miniconda
conda activate /gpfs/gibbs/pi/gerstein/hc865/conda_envs/sm_env

snakemake \
  --profile profiles/slurm/ \
  --config flatten_beds=True \
  --rerun-incomplete \
  --keep-going \
  --jobs 10 \
  --latency-wait 60 \
  > snakemake.flatten.log 2>&1