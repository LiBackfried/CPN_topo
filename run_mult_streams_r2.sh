#!/bin/bash
#SBATCH -J N21_nest_sampling
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_gratis
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=20:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

module load OpenSSL/1.1

## 2nd run now also with 5xcounter limit for the constraint fullfillment!

srun --export=ALL /bin/bash -c '
idx=$((SLURM_PROCID+4))
outdir="./out_data/res_${idx}"
mkdir -p "$outdir"

./cpn_ns config_files/N21_L72_${SLURM_PROCID}
'

module purge
