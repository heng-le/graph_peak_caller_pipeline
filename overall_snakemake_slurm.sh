#!/usr/bin/env bash
#SBATCH --partition=scavenge
#SBATCH --mem=20G
#SBATCH --time=1-00:00:00
#SBATCH -c 1
#SBATCH --account=gerstein
#SBATCH --job-name=snakemake_driver
#SBATCH --output=logs/slurm/snakemake_driver.%j.out
#SBATCH --error=logs/slurm/snakemake_driver.%j.err

set -euo pipefail

module purge 
module load miniconda
conda activate /gpfs/gibbs/pi/gerstein/hc865/conda_envs/sm_env

cd /gpfs/gibbs/pi/gerstein/hc865/gpc_sm_v2

export PATH="/gpfs/gibbs/pi/gerstein/hc865/downloads/vg_old:$PATH"

snakemake --profile profiles/slurm
