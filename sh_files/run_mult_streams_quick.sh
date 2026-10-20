#!/bin/bash
#SBATCH -J N21_nest_sampling_quick
#SBATCH --account=gratis
#SBATCH --partition epyc2
#SBATCH --qos job_gratis
#SBATCH --ntasks=10
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=18:00:00
#SBATCH --chdir=/storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
#SBATCH --mail-user=liane.backfried@unibe.ch
#SBATCH --mail-type=end,fail

module load OpenSSL/1.1

## 2nd run now also with 5xcounter limit for the constraint fullfillment!

srun --export=ALL /bin/bash -c '
./cpn_ns config_files/quick_parallel_runs/config_run_${SLURM_PROCID}
'

module purge
