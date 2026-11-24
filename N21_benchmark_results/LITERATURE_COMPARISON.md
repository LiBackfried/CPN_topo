# N=21 literature comparisons

## Bonanno's 2017 master's thesis

Reference: Claudio Bonanno, master's thesis, University of Pisa, academic year
2016/2017; **Table 4.2, printed page 72 (PDF page 74)**. The full title and a
reusable citation are in [references.bib](literature/references.bib).
[University thesis record](https://etd.adm.unipi.it/t/etd-09262017-185353/) ·
[Table in the public PDF](https://etd.adm.unipi.it/theses/available/etd-09262017-185353/unrestricted/Tesi_Bonanno_Claudio.pdf#page=74).

The source was identified by the user and verified against the PDF already in
the user's Zotero library. The matching local attachment is
[Tesi_Bonanno_Claudio.pdf](/C:/Users/libac/Zotero/storage/4DX42BMR/Tesi_Bonanno_Claudio.pdf),
Zotero attachment key `4DX42BMR`. The live library was locked, so the attachment
record was located through a read-only 23 November Zotero database backup; the
actual PDF was then read directly. No Zotero record was edited and no PDF was
downloaded. The original image and a rendered source page are preserved:

- [User-supplied reference image](literature/bonanno_table_4_2_user_reference.png).
- [Verified thesis page 72](literature/bonanno_thesis_page72.png).
- [Reference values and derived comparisons](literature/bonanno_2017_comparison.json).

## Transcribed reference values

Both blocks have N=21, L=72 and theta=0. Parentheses give uncertainty in the
last printed digits; for example, `1.716722(2)` means `1.716722 +/- 0.000002`.
The two methods are retained separately, without combining their estimates.

| beta | Observable | Local algorithm | Simulated tempering |
| ---: | --- | ---: | ---: |
| 0.60 | E_L / (N V) | 1.716722(9) | 1.716722(2) |
| 0.60 | xi_L | 2.95(4) | 2.895(7) |
| 0.60 | Mean cooled Q_U | 0.01(3) | 0.002(3) |
| 0.60 | V chi_L | 4.97(6) | 4.943(8) |
| 0.61 | E_L / (N V) | 1.687653(9) | 1.687663(2) |
| 0.61 | xi_L | 3.01(4) | 3.011(8) |
| 0.61 | Mean cooled Q_U | -0.02(3) | 0.002(2) |
| 0.61 | V chi_L | 4.26(8) | 4.327(6) |

Values were checked against both the supplied image and the local thesis page.
Only the beta=0.60 block is compared below. The beta=0.61 values are saved for a
future beta-reweighted analysis; beta=0.60 estimates cannot be compared directly
with that block.

## Matching observables

Use the weighted 5,000-update UBELIX estimates, replacement analysis **23353908**.
Their source is [ubelix_reported_results.json](ubelix_reported_results.json),
transcribed from the user's remote terminal output. Raw remote data and
bootstrap replicas were not independently inspected.

The lattice volume is `V = 72^2 = 5184`. The current NS analysis maps to the
reference observables as follows:

| Reference quantity | NS quantity and conversion |
| --- | --- |
| Positive tabulated E_L / (N V) | `mean_energy = 2 * mean_action_density = mean_extensive_energy / (N*V)` |
| xi_L squared | `xi_L_squared = (mean_G0/mean_Gk - 1) / (4*sin(pi/L)^2)` |
| Mean cooled Q_U | `mean_Q_U`, evaluated after 50 cooling sweeps |
| V chi_L | `5184 * chi_topological`, with error `5184 * SE(chi_topological)` |

The thesis and current code use Symanzik coefficients `c1=4/3`, `c2=-1/12` and
the same second-moment correlation-length expression (thesis sections 2.2 and
2.4). Energy comparison uses the positive convention printed in Table 4.2.
The thesis drops additive constants when writing its action; the current
`energy_density` retains them. Do not compare the table to the unshifted
negative bond-energy expression, to raw epsilon (a factor of two smaller), or
to `mean_symanzik_action/(N*V)` (which contains an additional beta).

The current susceptibility is centered: `V*chi_topological = Var(Q_U)`, not
the uncentered `mean_Q_U_squared`. Their finite-sample difference is
`mean_Q_U^2`. Multiplying the reported susceptibility error by V preserves the
bootstrap's covariance treatment; independently combining errors on charge
moments would not. At theta=0 the theoretical charge mean vanishes, so the
centered variance and second moment have the same ensemble limit.

The reference charge is the cooled U-geometric charge. The exact cooling count
used for Table 4.2 was not established from the inspected material; matching
charge definitions does not by itself establish identical cooling systematics.

## beta=0.60 numerical comparison

The simulated-tempering column supplies the more precise reference errors in
this table. Both thesis methods are included in the JSON calculations.

| Matched observable | Thesis simulated tempering | NS: 15,500 proposals | NS: 31,000 proposals |
| --- | ---: | ---: | ---: |
| E_L / (N V) | 1.716722 +/- 0.000002 | 1.7164125 +/- 0.0001872 | 1.7168640 +/- 0.0002093 |
| xi_L squared | 8.3810 +/- 0.0405 | 13.7767 +/- 4.0669 | 7.7874 +/- 4.6994 |
| Mean cooled Q_U | 0.002 +/- 0.003 | 0.3194 +/- 0.4219 | -0.0020 +/- 0.5279 |
| V chi_L, centered NS estimator | 4.943 +/- 0.008 | 3.9361 +/- 1.0717 | 4.3496 +/- 0.8272 |

For the reference xi_L-squared value, the point estimate is `xi_L^2` and its
error uses first-order propagation `SE(xi_L^2) = 2*xi_L*SE(xi_L)`. This is a
derived comparison quantity, not an additional directly reported thesis result.
Using xi_L squared avoids the undefined NS xi_L bootstrap uncertainty in the
31,000-proposal arm; that undefined error remains preserved in the benchmark
records rather than being replaced with zero or dropping invalid replicas.

Differences below are `(NS - reference) / sqrt(SE_NS^2 + SE_reference^2)`, assuming
independent reference and NS errors:

| Observable | 15,500 vs simulated tempering | 31,000 vs simulated tempering |
| --- | ---: | ---: |
| E_L / (N V) | -1.653 | +0.678 |
| xi_L squared | +1.327 | -0.126 |
| Mean cooled Q_U | +0.752 | -0.008 |
| V chi_L | -0.939 | -0.717 |

No listed marginal discrepancy exceeds 1.66 combined standard errors, including
comparisons with the local-algorithm reference. This is a useful external
consistency check at the present precision. NS errors are much larger than the
reference errors; agreement does not establish unbiased constrained sampling,
adequate initialization or a precise determination of xi_L. The observables are
correlated, so the residuals must not be treated as an independent joint test.

The literature reference is now available; a matched direct MCMC control with
the current executable, measurement/cooling choices and recorded equilibration
still provides a separate diagnostic. Nothing here establishes a useful beta
reweighting range or a result at beta=0.61.

## Berni, Bonanno and D'Elia (2019)

These N=21, θ=0 finite-lattice reference points come from Table II. The
lattice sizes come from Table I. [Table I](https://arxiv.org/pdf/1911.03384#page=6)
· [Table II](https://arxiv.org/pdf/1911.03384#page=8)
· [Published article](https://doi.org/10.1103/PhysRevD.100.114509)

| β_L | L | ξ_L | 10³ a²χ | 10³ ξ²χ |
| ---: | ---: | ---: | ---: | ---: |
| 0.68 | 102 | 4.772(4) | 0.3404(6) | 7.750(18) |
| 0.70 | 114 | 5.409(4) | 0.2647(4) | 7.746(16) |

Both points were measured directly at θ=0 using the geometric link charge
after 25 cooling sweeps. Table II gives dashes for `Z`, `b_2`, `b_4`,
reduced χ² and degrees of freedom for these rows. The paper reports the
uncertainty on the product ξ²χ directly, so use it for comparisons.
[Paper, Sec. 3 A and Tables I–II](https://arxiv.org/pdf/1911.03384)

A matched NS comparison should use the corresponding β and lattice size, and
select 25 cooling sweeps for the charge measurements with `--cooling-step 25`.
The NS quantity `chi_topological` is in lattice units (a²χ). To compare the product,
evaluate `xi_L_squared * chi_topological` within each bootstrap replicate so
the uncertainty includes their covariance.

The [reference JSON](literature/berni_bonanno_delia_2019_n21.json) preserves the
table scales and unscaled values. The [supplied table excerpt](literature/berni_bonanno_delia_table_ii_user_reference.png)
and [BibTeX citation](literature/references.bib) are saved alongside it.
