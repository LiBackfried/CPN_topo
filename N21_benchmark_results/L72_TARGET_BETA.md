# N=21 target-beta analysis at L=72

The study range is β=0.68–0.76. First [increase the β=0.60 statistics and
validate reweighting to β=0.61](L72_NEAR_SOURCE.md). The wider screen uses
β=0.68, 0.70, 0.72, 0.74 and 0.76 at θ=0. The command below can screen the
two original 5,000-update β=0.60 ensembles separately once that validation
has been reviewed.

## Finite volume

Treat the L=72 results as finite-volume observables. Using the published
larger-volume correlation lengths as proxies, `72² / (21 ξ_L²)` is about
10.8 at β=0.68 and 8.4 at β=0.70. The corresponding published ensembles are
L=102 and L=114, with ratios of about 20 and 21. The proxies illustrate why
volume effects matter for topology. Their size at L=72 and their evolution
across the target range require measurements. [Berni et al., Table I and Sec. 4 A](https://arxiv.org/pdf/1911.03384#page=7)

Use direct MCMC at the same N, L and β to check reweighting. Start with β=0.68
and 0.76 to bracket the range. Check topological tunneling and block errors in
the reference chains. Compare across volumes separately at fixed β. The
[published points](LITERATURE_COMPARISON.md#berni-bonanno-and-delia-2019) give
larger-volume context at β=0.68 and 0.70.

## Run the depth scan on UBELIX

Sync `N4_volume_benchmark/scan_depth.py` and
`N21_L72_ubelix_benchmark/scan_targets_ubelix.sh` to UBELIX. Run the following
from the repository root.

```bash
cd /storage/homefs/lb25v444/cpn_nestsampl/CPN_topo
campaign=/scratch/network/users/lb25v444/out_data/ns_N21_L72_benchmark.5NegZsTv
sbatch --ntasks=1 --cpus-per-task=1 \
  --output="$campaign/target_scan_%j.out" --error="$campaign/target_scan_%j.err" \
  N21_L72_ubelix_benchmark/scan_targets_ubelix.sh "$campaign"
```

The job reads simulation jobs 23350970 and 23350971 and writes
`target_scan_<job_ID>/p15500_depth.csv` and `p31000_depth.csv` under that campaign.
The `completed` marker appears after both scans succeed. Each CSV covers prefixes
of 1,000, 2,000, 3,500 and 5,000 updates with a common low-energy cutoff across
streams at each prefix. The scan uses 200 paired whole-stream bootstrap draws
within each arm. The two arms use independent seeds. Charge measurements use
cooling step 25 for alignment with Berni et al.; the product ξ²χ is evaluated
within each bootstrap draw.

## Read the results

The local smoke check used three 100-update L=72 streams with 15,500 proposals
per update. With the 100-update prefix, the last tenth of retained energy
ranks carried 97.64% of the observed weight at β=0.68 and 99.95% at β=0.76.
These short streams are cutoff dominated across the range. The 5,000-update
campaign requires its own scan on UBELIX.

Follow where the target weight lies as the prefix grows. Weight piling up in
the last tenth of the retained energy ranks or a 99% weight point close to the
cutoff calls for more low-energy coverage. Check that energy, ξ², susceptibility
and ξ²χ stabilize with depth relative to their paired bootstrap variation.
Check stream weight concentration and nonzero-charge weight before interpreting
topological estimates. Quadrature and stream weight ESS describe weight
concentration. The conditional bound on missing target weight can be loose.

The upper end of the range is a coverage test for the β=0.60 streams. If they
remain cutoff dominated, plan a fresh source closer to the target range, such
as β=0.68, and validate its initialization and overlap before extending to
β=0.76. Report the L=72 estimates with the depth and sampling checks that
support them.
