#!/bin/bash
#SBATCH --job-name=find_stats
#SBATCH --partition=bigmem
#SBATCH --time=1-00:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=500G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=heng-le.chen@yale.edu
#SBATCH --output=logs/find_stats-%j.txt

module purge
module load miniconda
conda activate /gpfs/gibbs/pi/gerstein/hc865/cvenv/

python scripts/calculate_stats.py
