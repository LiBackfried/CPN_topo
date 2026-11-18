from pathlib import Path
from tempfile import TemporaryDirectory
import csv
import json
import unittest

import numpy as np

from N4_volume_benchmark.scan_volume_betas import BETAS, analyze, beta_quantities, select_runs
from N4_volume_benchmark.plot_volume_betas import compare, complete_mcmc_root, read_scan
from utils.nest_sampl import NestedSamplingStream, combine_streams


def make_ns(root, lattice, stoc, seeds=(1, 2)):
    for seed in seeds:
        path = root / f"run_{seed}"
        path.mkdir(parents=True)
        count = 41
        (path / "input.conf").write_text(
            f"size {lattice} {lattice}\nbeta 0.7\ntheta 0\nrng_seed {seed}\nstart 1\nrng_start 0\n"
            f"num_ns_meas {count}\nnum_live_pts 50\nnum_single_site_stoc_upd {stoc}\n"
            "num_cool_step 50\nmeas_cool_every 50\n", encoding="utf-8")
        (path / "log.dat").write_text("Theory: 2d CP^{N-1} model with N = 4\n\nSimulation end: done\n")
        step = np.arange(count)
        epsilon = np.linspace(0.8, 0.5, count) + seed * 0.0001
        np.savetxt(path / "dati.dat", np.column_stack((step, epsilon, 4 + epsilon, 1 + epsilon / 5)))
        rows = [[i, cool, (i + seed) % 3 - 1, 0, 0] for i in step for cool in (0, 50)]
        np.savetxt(path / "topo.dat", rows)
        np.savetxt(path / "acceptance_rate.dat", np.arange(1, count), fmt="%d")


def make_mc(root, lattice, beta):
    for seed in (1, 2, 3):
        path = root / f"run_{seed}"
        path.mkdir(parents=True)
        (path / "input.conf").write_text(
            f"size {lattice} {lattice}\nbeta {beta}\ntheta 0\nrng_seed {seed}\nstart 1\n"
            "num_MC_step 640\nmeas_every 10\nnum_cool_step 50\nmeas_cool_every 50\n"
            "data_file dati.dat\ntopo_file topo.dat\n", encoding="utf-8")
        (path / "log.dat").write_text("Theory: 2d CP^{N-1} model with N = 4\n\nSimulation end: done\n")
        steps = np.arange(10, 641, 10)
        q = np.sin(steps + seed)
        np.savetxt(path / "dati.dat", np.column_stack((steps, 0.5 + q / 100, 4 + q / 10, 1 + q / 20)), fmt="%.12g")
        np.savetxt(path / "topo.dat", [[i, c, v] for i, v in zip(steps, q) for c in (0, 50)], fmt="%.12g")


class VolumeScanTests(unittest.TestCase):
    def test_subsets_are_reproducible_and_unselected_measurements_are_not_loaded(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_ns(root / "raw", 22, 1500, seeds=range(1, 7))
            candidates = sorted((root / "raw").iterdir())
            selected = select_runs(candidates, 3, 123)
            self.assertEqual(selected, select_runs(list(reversed(candidates)), 3, 123))
            self.assertEqual(len(set(selected)), 3)
            for path in set(candidates) - set(selected):
                (path / "log.dat").write_text("unselected data must never be loaded")
            analyze([root / "raw"], 3, 1234, root / "output", 22, 1500, 3,
                    max_streams=3, selection_seed=123, expected_available_chains=6)
            provenance = json.loads((root / "output/inputs.json").read_text())
            self.assertEqual([Path(path) for path in provenance["runs"]], selected)
            self.assertEqual(provenance["available_chains"], 6)
            self.assertTrue(all(row["chains"] == 3 for row in read_scan(root / "output/beta_scan.csv", 22)))
            with self.assertRaisesRegex(ValueError, "between 2 and 6"):
                select_runs(candidates, 7)

    def test_beta_weights_and_volume_normalization_against_explicit_sum(self):
        epsilon = np.array([0.8, 0.7, 0.6])
        q = np.array([-1.0, 0.0, 2.0])
        observables = dict(action_density=epsilon, energy=2 * epsilon, q_u=q,
                           q_z=q, q_plaq=q, g0=np.array([3., 4., 5.]), gk=np.ones(3))
        data = combine_streams([NestedSamplingStream(2 * epsilon, observables, 50)])
        for lattice in (22, 38):
            for beta in BETAS:
                raw = (np.exp(-np.arange(3) / 50) - np.exp(-np.arange(1, 4) / 50))
                exponent = -(beta - 0.7) * 8 * lattice**2 * epsilon
                raw *= np.exp(exponent - exponent.max())
                w = raw / raw.sum()
                actual = beta_quantities(data, lattice, beta)
                self.assertAlmostEqual(actual["mean_action_density"], np.dot(w, epsilon))
                expected_chi = np.dot(w, (q - np.dot(w, q))**2) / lattice**2
                self.assertAlmostEqual(actual["chi_topological"], expected_chi)
                xi2 = (np.dot(w, observables["g0"]) - 1) / (4 * np.sin(np.pi / lattice)**2)
                self.assertAlmostEqual(actual["xi_L_over_L"], np.sqrt(xi2) / lattice)

    def test_scan_and_comparison_with_direct_mcmc(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for lattice, stoc in ((22, 1500), (38, 8664)):
                raw, output = root / f"raw{lattice}", root / f"L{lattice}"
                make_ns(raw, lattice, stoc)
                analyze([raw], 3, 123, output, lattice, stoc, 2)
                rows = read_scan(output / "beta_scan.csv", lattice)
                self.assertEqual(len(rows), 7)
                self.assertEqual(rows[0]["xi_L_over_L_bootstrap_finite_fraction"], 1)
            mc = root / "mcmc38"
            make_mc(mc, 38, 1.0)
            self.assertTrue(complete_mcmc_root(mc))
            compare(root / "L22/beta_scan.csv", root / "L38/beta_scan.csv", root / "comparison",
                    mcmc_l38=mc, burn_in=0, block_size=4)
            with (root / "comparison/volume_comparison.csv").open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), 15)
            reference = next(row for row in rows if row["method"] == "MCMC")
            self.assertEqual(float(reference["target_beta"]), 1.0)
            self.assertTrue(float(reference["xi_L_over_L_se"]) > 0)
            for name in ("volume_shifts.csv", "ns_mcmc_comparison.csv", "volume_dependence.png",
                         "volume_dependence.pdf", "coverage_diagnostics.png", "mcmc_L38_binning.csv"):
                self.assertTrue((root / "comparison" / name).stat().st_size > 0)
            # An unfinished raw reference must not silently become a comparison.
            (mc / "run_1/dati.dat").write_text("10 .5 4 1\n")
            self.assertFalse(complete_mcmc_root(mc))

    def test_scan_refuses_wrong_proposal_count(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_ns(root / "raw", 38, 4332)
            with self.assertRaisesRegex(ValueError, "8664 stochastic proposals"):
                analyze([root / "raw"], 3, 123, root / "output", 38, 8664, 2)


if __name__ == "__main__":
    unittest.main()
