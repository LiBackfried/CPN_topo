# Export and plot all N=4 charge moments

From the updated CPN_topo checkout on UBELIX, submit:

```bash
sbatch N4_volume_benchmark/export_charge_moments_ubelix.sh
```

The launcher uses `export_charge_moments.py` and the saved selection manifests
already in this repository. Copy both new scripts and the manifests with the
checkout. This is analysis of existing scratch data; no simulation is launched.

The five array elements run at most one at a time. Each requests one CPU,
16 GiB and four hours. Array indices 0,1,2,3,4 correspond to L=22,38,66,90,120.
For example, analyze only the two largest volumes with:

```bash
sbatch --array=3-4%1 N4_volume_benchmark/export_charge_moments_ubelix.sh
```

The default scratch root is `/scratch/network/users/lb25v444/out_data`;
override it with `VOLUME_DATA_ROOT=/absolute/path/to/out_data` if needed.

| L | NS streams | Updates per stream | NS target beta | Direct MCMC beta |
|---:|---:|---:|---|---:|
| 22 | 100 selected from 800, exactly as in the saved scan | 50,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 0.70 |
| 38 | 24 | 35,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 1.00 |
| 66 | 12 | 110,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 0.90 |
| 90 | 12 | 210,000 | 0.90, 0.95, 1.00 | 0.95 |
| 120 | 12 | 300,000 | 0.90, 0.95, 1.00 | 1.00 |

All NS inputs have source beta=0.70, theta=0 and compile-time N=4. The loader
follows continuation parents and removes repeated boundary measurements. It
uses the same common-energy-support prefix convention as the existing scans.
The raw topology columns provide Q_U, Q_z and Q_plaquette at the last recorded
cooling step. Each second moment averages the squared measurements.

Errors use 200 whole-stream NS bootstrap replicates, remerging and reweighting
each replicate. MCMC uses three chains, discards measurements through MC step
20,000, and uses a delete-one-block jackknife with 128 measurements per block.
Incomplete block tails are dropped separately in each chain. Optional variables
are `N_BOOTSTRAP`, `BOOTSTRAP_SEED`, `MCMC_BURN_IN` and `MCMC_BLOCK_SIZE`.

Each volume writes its own new directory:

```text
N4_L<L>_res/charge_moments/job_<ARRAY_JOB_ID>/
    ns_charge_moments.csv
    mcmc_charge_moments.csv
    charge_moments.csv
    inputs.json
    completed
```

Existing output directories are not overwritten. The `completed` marker is
written only after both analyses finish. Slurm logs are
`N4_charge_moments_<ARRAY_JOB_ID>_<ARRAY_INDEX>.log` in the submission directory.

Copy these five output directories back into the same local repository paths,
then regenerate the plot:

```bash
python N4_volume_benchmark/plot_charge_moments.py
```

The plotter selects the highest numbered completed export per volume and makes
six panels with open markers, a blue NS gradient and an orange MCMC gradient.
Outputs go to `N4_volume_benchmark/summary_figures_20261123/charge_moments.*`.
