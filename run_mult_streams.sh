#!/bin/bash
#SBATCH -J N21_nest_sampling
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_gratis
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH --time=12:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

module load OpenSSL/1.1

# 8 doesnt work for some reason, but 4 does... => also dont have it saving to the scratch that gives seg fault for some reason
# mkdir -p /scratch/network/users/lb25v444/cpn_ns_N21

# having the outdir defined outside the srun doesnt work->no procid defined yet?!

#srun bash -c '
#outdir="/scratch/network/users/lb25v444/cpn_ns_N21/res_${SLURM_PROCID}"
#mkdir -p "$outdir"

#./cpn_ns config_files/nest_${SLURM_PROCID}
#'

srun --export=ALL /bin/bash -c '
outdir="./out_data/res_${SLURM_PROCID}"
mkdir -p "$outdir"

./cpn_ns config_files/debug_ubelix_${SLURM_PROCID}
'

module purge
