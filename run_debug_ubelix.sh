#!/bin/bash
#SBATCH -J N21_nest_sampling_debug
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_debug
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=00:20:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo

module purge
module load OpenSSL/1.1

#mkdir -p /scratch/network/users/lb25v444/cpn_ns_N21

# so i think the problem lies with the bash after the srun at this point! in the future, make the directories to the best knowledge and only try srun! 
#srun --export=ALL cpn_ns config_files/nest_debug
./cpn_ns config_files/debug_ubelix

module purge
