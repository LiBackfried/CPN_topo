# Charge-distribution export and plots

## L120 baseline versus doubled proposals

The locally pulled L120 summaries contain moments but no histogram exports
or raw charge histories. A measured distribution cannot be reconstructed
from those moments. For the completed comparison 23502241, sync the new
`plot_L120_proposal_charges.py` and `plot_L120_proposal_charges_ubelix.sh`,
then submit from the UBELIX checkout root:

```bash
sbatch N4_volume_benchmark/plot_L120_proposal_charges_ubelix.sh
```

This is a single analysis job (one CPU, 8 GiB, four hours), with no simulation
or rebuild. It reads the baseline24 and control8 selections from the completed
proposal comparison's `inputs.json` and reuses MCMC 22780263. It exports
separate canonical beta=1 histograms for 86400 and 172800 proposals, each at
300k updates/stream, and compares them with the shared MCMC reference.
The source beta is 0.7, and final cooling is 50 sweeps. NS errors use 200
whole-stream bootstrap draws per cohort; MC uses the same cut 20000 and
block 512 measurements as the proposal comparison. Charges are binned as
measured in unit-width bins centered on integers, with no rounding or
symmetrization. The usual common-energy-prefix convention is applied
separately within each cohort; both have observational depth convergence.

Output is `N4_L120_res/proposal_charge_distributions/job_<JOB_ID>/`, containing
per-cohort CSVs/provenance and `comparison/L120_Q_U_proposal_comparison.png`
(also PDF). Equivalent Q_z and Q_plaquette figures are included. Each figure
has linear and log panels, open markers, and statistical errors. The visible
charge range covers bins with any probability at least 1e-6; the complete
normalized histograms are retained in CSV without tail renormalization.
The two exports must give matching MCMC histograms/errors before overlaying.

Pull that directory back for local viewing. Replot without raw data using:

```bash
python N4_volume_benchmark/plot_L120_proposal_charges.py plot \
  N4_L120_res/proposal_charge_distributions/job_JOBID
```

## Existing volume export

Submit from the updated repository checkout on UBELIX:

```bash
sbatch N4_volume_benchmark/plot_charge_distributions_ubelix.sh
```

The launcher uses `plot_charge_distributions.py` and the existing analysis
helpers and selection manifests. Copy the updated checkout before submission.
The array maps 0,1,2,3,4 to L=22,38,66,90,120, with one element running at a
time. Each element requests one CPU, 16 GiB, and four hours. Select a subset
with e.g. `sbatch --array=3-4%1 ...`.

The job reads existing NS and MCMC scratch outputs. It exports histograms of
Q_U, Q_z, and Q_plaquette at the final recorded cooling step and makes linear
and logarithmic probability plots, three panels per target beta. The blue NS
and orange MCMC volume gradients use open circles and diamonds respectively.

| L | NS streams | NS updates/stream | NS target beta | MCMC beta |
|---:|---:|---:|---|---:|
| 22 | 100 from the saved selection | 50,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 0.70 |
| 38 | 24 | 35,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 1.00 |
| 66 | 12 | 110,000 | 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00 | 0.90 |
| 90 | 12 | 210,000 | 0.90, 0.95, 1.00 | 0.95 |
| 120 | **24**, using completed analysis 23350708 | 300,000 | 0.90, 0.95, 1.00 | 1.00 |

L120 automatically selects `combined24x300_analysis_23350708/inputs.tsv` when
that file and its completion marker exist. If absent, it uses the earlier
twelve-stream selection. The exact paths and actual stream count are saved
in the new output's `inputs.json`. Other volumes retain the previous charge
analysis selections. Override a selection using an `inputs.tsv` or the charge
moment export's `inputs.json`, for example:

```bash
NS_MANIFEST_L120="$PWD/N4_L120_res/combined300_ns22885157_analysis_22904265/inputs.tsv" \
  sbatch --array=4 N4_volume_benchmark/plot_charge_distributions_ubelix.sh
```

NS uses source beta=0.70, theta=0, compile-time N=4, and the existing common
energy-support prefix convention. Continuation parents are joined with the
repeated checkpoint row removed. The histograms use canonical quadrature
weights, with beta reweighting applied separately at every requested target.
Errors resample whole independently seeded streams, remerge, and reweight
on every one of 200 bootstrap draws. Individual dead points are never treated
as independent samples.

MCMC curves appear only at their direct simulation beta. Measurements through
MC step 20,000 are discarded. Histogram errors use a delete-one-block
jackknife with blocks of 128 measurements; blocks never cross chains and
incomplete tails are discarded independently in each chain.

Bins have width one by default, centered on integer charges. Charges are
binned as measured, without rounding or symmetrizing. Every bin probability
is a probability mass, not a density per unit Q, and the full histogram sums
to one. NS and MCMC share edges for each charge/volume. Plotting multiple
exports rejects inconsistent bin widths. `CHARGE_BIN_WIDTH=0.25` requests
finer bins, including for the continuous plaquette charge. Set the same width
for all volumes that will appear in the same plot.

The log figure displays probabilities down to `PROBABILITY_FLOOR=1e-6`.
Zero bins and nonpositive error-bar limits are masked in that view; the CSV
retains every bin and its original error, and no cropped tail is renormalized.
Errors in different bins are correlated. Other optional environment variables
are `VOLUME_DATA_ROOT` (default `/scratch/network/users/lb25v444/out_data`),
`N_BOOTSTRAP`, `BOOTSTRAP_SEED`, `MCMC_BURN_IN`, and `MCMC_BLOCK_SIZE`.

Each volume writes a new directory, refusing to overwrite existing output:

```text
N4_L<L>_res/charge_distributions/job_<ARRAY_JOB_ID>/
    charge_distributions.csv
    inputs.json
    charge_distributions_beta<TARGET>_linear.png / .pdf
    charge_distributions_beta<TARGET>_log.png / .pdf
    completed
```

Copy these directories back to the same local repository paths. Make volume
overlays at fixed beta without accessing the raw data:

```bash
python N4_volume_benchmark/plot_charge_distributions.py plot
```

This selects the highest numbered completed export per available volume and
writes figures to `N4_volume_benchmark/charge_distribution_figures/`. You can
also pass explicit histogram CSVs and an output directory:

```bash
python N4_volume_benchmark/plot_charge_distributions.py plot \
  N4_L22_res/charge_distributions/job_JOBID/charge_distributions.csv \
  N4_L38_res/charge_distributions/job_JOBID/charge_distributions.csv \
  --output N4_volume_benchmark/my_charge_distributions
```

For an explicit local NS-only data selection:

```bash
python N4_volume_benchmark/plot_charge_distributions.py analyze \
  --lattice 22 --ns ../data_N4_UBELIX/run_750 ../data_N4_UBELIX/run_751 \
  --updates 50000 --targets 0.70 0.75 --bootstrap 200 \
  --output N4_L22_res/charge_distributions/local_two_streams
```

The local command's stream count differs from the production selection and
is recorded explicitly. Moment summaries alone cannot reconstruct these
histograms; only the analysis command needs the raw data.
