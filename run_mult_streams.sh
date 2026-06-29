#!/bin/bash
#SBATCH -J debug_nest_sampling
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_debug
#SBATCH --ntasks=8
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=00:20:00
#SBATCH --chdir=/storage/homefs/lb25v444/CPN_nestsamp/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

mkdir -p /scratch/network/users/lb25v444/cpn_ns_N21

outdir="/scratch/network/users/lb25v444/cpn_ns_N21/res_${SLURM_PROCID}"
mkdir -p "$outdir"

srun bash -c './cpn_ns config_files/nest_${SLURM_PROCID}'