from pathlib import Path
from tempfile import TemporaryDirectory
import csv
import json
import unittest

import numpy as np

from N4_volume_benchmark.scan_volume_betas import BETAS, analyze, beta_quantities, select_runs
from N4_volume_benchmark.plot_volume_betas import compare, complete_mcmc_root, read_scan
from N4_volume_benchmark.plot_beta_weights import single_run_weights
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
    def test_single_stream_weights_normalize_each_beta_and_use_its_own_live_count(self):
        epsilon = np.array([0.8, 0.7, 0.6, 0.5])
        betas = (0.7, 0.7001, 0.85, 1.0)
        for lattice in (22, 38, 66):
            data = single_run_weights(epsilon, lattice, 50, betas)
            np.testing.assert_allclose(data["normalized_weight"].sum(axis=1), 1, atol=1e-12)
            for index, beta in enumerate(betas):
                exponent = -np.arange(len(epsilon))/50 - (beta-0.7)*8*lattice*lattice*epsilon
                expected = np.exp(exponent-exponent.max())
                expected /= expected.sum()
                np.testing.assert_allclose(data["normalized_weight"][index], expected, rtol=1e-12, atol=1e-14)
            np.testing.assert_allclose(data["log_x"], -np.arange(1, len(epsilon)+1)/50)

    def test_single_stream_log_weights_preserve_underflowed_tails(self):
        data = single_run_weights(np.linspace(0.8, 0.4, 2000), 22, 1)
        self.assertEqual(data["normalized_weight"][0, -1], 0)
        self.assertTrue(np.isfinite(data["log_normalized_weight"]).all())
        np.testing.assert_allclose(data["normalized_weight"].sum(axis=1), 1, atol=1e-12)

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
                with np.load(output / "normalized_weights_single_run.npz") as weights:
                    self.assertEqual(weights["normalized_weight"].shape, (7, 41))
                provenance = json.loads((output / "normalized_weights_single_run.json").read_text())
                self.assertEqual(provenance["num_live_pts"], 50)
                self.assertEqual(provenance["points"], 41)
                for name in ("normalized_weights_single_run.png", "normalized_weights_single_run.pdf",
                             "normalized_weights_single_run_log.png", "normalized_weights_single_run_log.pdf"):
                    self.assertTrue((output / name).stat().st_size > 0)
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

    def test_l66_scan_and_three_volume_comparison_preserve_unresolved_xi(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for lattice, stoc in ((22, 1500), (38, 8664), (66, 26136)):
                make_ns(root / f"raw{lattice}", lattice, stoc)
                analyze([root / f"raw{lattice}"], 3, 123, root / f"L{lattice}", lattice, stoc, 2)
            path = root / "L66/beta_scan.csv"
            with path.open() as file:
                rows = list(csv.DictReader(file))
            for row in rows[:2]:
                row.update(xi_L_squared=-9.0, xi_L_squared_bootstrap_se=22.0,
                           xi_L="nan", xi_L_over_L="nan", xi_L_bootstrap_se="nan",
                           xi_L_over_L_bootstrap_se="nan")
            with path.open("w", newline="") as file:
                writer = csv.DictWriter(file, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            make_mc(root / "mc66", 66, 0.9)
            compare(root / "L22/beta_scan.csv", root / "L38/beta_scan.csv", root / "comparison",
                    l66=path, mcmc_l66=root / "mc66", burn_in=0, block_size=4)
            with (root / "comparison/volume_comparison.csv").open() as file:
                points = list(csv.DictReader(file))
            self.assertEqual(len(points), 22)
            unresolved = [row for row in points if row["L"] == "66.0" and float(row["target_beta"]) < 0.8]
            self.assertEqual(len(unresolved), 2)
            self.assertTrue(all(row["xi_status"] == "undefined" for row in unresolved))
            self.assertTrue(all(float(row["xi_L_squared"]) == -9 for row in unresolved))
            with (root / "comparison/volume_shifts.csv").open() as file:
                shifts = list(csv.DictReader(file))
            self.assertEqual({(row["L_small"], row["L_large"]) for row in shifts},
                             {("22", "38"), ("22", "66"), ("38", "66")})
            with (root / "comparison/ns_mcmc_comparison.csv").open() as file:
                checks = list(csv.DictReader(file))
            self.assertEqual({(float(row["L"]), float(row["target_beta"])) for row in checks}, {(66, 0.9)})
            self.assertTrue((root / "comparison/volume_dependence.png").is_file())
            wrong = root / "L66_wrong.csv"
            for row in rows:
                row["stochastic_proposals"] = 8664
            with wrong.open("w", newline="") as file:
                writer = csv.DictWriter(file, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaisesRegex(ValueError, "26136 stochastic proposals"):
                read_scan(wrong, 66)


if __name__ == "__main__":
    unittest.main()
