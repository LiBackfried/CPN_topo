#!/bin/bash
# Run from Ubuntu-24.04 WSL. Mock Slurm, but build and run the real C executable.
set -euo pipefail
setup=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd "$setup/.." && pwd -P)
for file in "$setup"/{build_N21_ubelix,submit_mcmc_ubelix,mcmc_job_ubelix}.sh; do
    bash -n "$file"
    if grep -q $'\r' "$file"; then exit 98; fi
done
work=$(mktemp -d /tmp/n21-mcmc-check.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
project="$work/project"
mkdir -p "$project/N21_L72_ubelix_benchmark" "$project/utils" "$work/bin"
cp -r "$repo/"{include,lib,src} "$project/"
cp "$repo/"{Makefile.am,configure.ac,script_build_code.sh} "$project/"
cp "$setup/"{build_N21_ubelix.sh,submit_mcmc_ubelix.sh,mcmc_job_ubelix.sh,analyze_mcmc.py} "$project/N21_L72_ubelix_benchmark/"
cp "$repo/utils/"{cpn_io.py,mcmc.py} "$project/utils/"
module() { return 0; }
srun() {
    local task
    while [[ $1 == --* ]]; do shift; done
    for ((task=0; task<SLURM_NTASKS; task++)); do SLURM_PROCID=$task "$@"; done
}
export -f module srun
ac_cv_header_openssl_md5_h=no bash "$project/N21_L72_ubelix_benchmark/build_N21_ubelix.sh" mcmc
cmp "$repo/include/macro.h" "$project/include/macro.h"
cat > "$work/bin/sbatch" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_SBATCH"
case $* in
    *' --dependency=afterok:99001 '*) echo '99002;cluster' ;;
    *) echo '99001;cluster' ;;
esac
SH
chmod +x "$work/bin/sbatch"
export PATH="$work/bin:$PATH" NS_SCRATCH="$work/scratch" MOCK_SBATCH="$work/submissions"
driver="$project/N21_L72_ubelix_benchmark/submit_mcmc_ubelix.sh"
bash "$driver" L150-timing 4 > "$work/submitted"
grep -F -- '--dependency=afterok:99001' "$MOCK_SBATCH"
campaign=$(sed -n 's/^Scratch campaign: //p' "$work/submitted")
[[ $(<"$campaign/analysis_output.txt") == "$project/N21_benchmark_results/mcmc_L150-timing_99002" ]]
export SLURM_NTASKS=4 SLURM_CPUS_PER_TASK=1
SLURM_JOB_ID=99001 bash "$campaign/snapshot/mcmc_job_ubelix.sh" run L150-timing "$campaign" 150 0.60 4 1
SLURM_JOB_ID=99003 bash "$campaign/snapshot/mcmc_job_ubelix.sh" run L72-b061 "$campaign" 72 0.61 20 10
for job in 99001 99003; do
    [[ -f $campaign/job_$job/completed ]]
    [[ $(grep -hFx 'start 1' "$campaign/job_$job"/run_*/input.conf | wc -l) == 4 ]]
done
echo 'PASS: isolated N=21 build, mocked submission, and real short L=72 and L=150 MCMC jobs.'
