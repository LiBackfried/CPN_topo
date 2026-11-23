import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import numpy as np

from N4_volume_benchmark.export_charge_moments import (
    QUANTITIES, analyze, blocked_charge_moments, charge_statistic, load_mc_charges, scratch_path,
)
from utils.nest_sampl import NestedSamplingStream, combine_streams
from N4_volume_benchmark import plot_charge_moments


def make_mc(root):
    for seed in (1, 2, 3):
        path = root / f"run_{seed}"
        path.mkdir(parents=True)
        (path / "input.conf").write_text(
            f"size 22 22\nbeta 0.7\ntheta 0\nrng_seed {seed}\nstart 1\n"
            "num_MC_step 640\nmeas_every 10\nnum_cool_step 50\nmeas_cool_every 50\n"
            "data_file dati.dat\ntopo_file topo.dat\n")
        (path / "log.dat").write_text("Theory: 2d CP^{N-1} model with N = 4\nSimulation end: done\n")
        steps = np.arange(10, 641, 10)
        q = (np.arange(len(steps)) + seed) % 3 - 1
        np.savetxt(path / "dati.dat", np.column_stack((steps, steps * 0 + .5, steps * 0 + 4, steps * 0 + 1)))
        np.savetxt(path / "topo.dat", [[step, cool, v, 2 * v + .2, .7 * v - .1]
                                      for step, v in zip(steps, q) for cool in (0, 50)])


def make_ns(root):
    paths = []
    for seed in (1, 2):
        path = root / f"run_{seed}"
        path.mkdir(parents=True)
        (path / "input.conf").write_text(
            f"size 22 22\nbeta 0.7\ntheta 0\nrng_seed {seed}\nstart 1\nrng_start 0\n"
            "num_ns_meas 41\nnum_live_pts 50\nnum_single_site_stoc_upd 1500\n"
            "num_cool_step 50\nmeas_cool_every 50\n")
        (path / "log.dat").write_text("Theory: 2d CP^{N-1} model with N = 4\nSimulation end: done\n")
        steps = np.arange(41)
        epsilon = np.linspace(.8, .5, 41) + seed * .0001
        np.savetxt(path / "dati.dat", np.column_stack((steps, epsilon, epsilon * 0 + 4, epsilon * 0 + 1)))
        np.savetxt(path / "topo.dat", [[step, cool, (step + seed) % 3 - 1, .3 * step, -.2 * step]
                                      for step in steps for cool in (0, 50)])
        np.savetxt(path / "acceptance_rate.dat", np.arange(1, 41), fmt="%d")
        paths.append(path)
    return paths


class ChargeMomentTests(unittest.TestCase):
    def test_reweighted_second_moments_match_explicit_weighted_squares(self):
        epsilon = np.array([.8, .7, .6])
        charges = {"q_u": np.array([-1., 0., 2.]), "q_z": np.array([2., -3., 1.]),
                   "q_plaq": np.array([.2, -.7, 1.4])}
        data = combine_streams([NestedSamplingStream(2 * epsilon,
                               {"energy": 2 * epsilon, "action_density": epsilon, **charges}, 50)])
        for beta in (.7, .7001):
            values = charge_statistic(data, 22, (beta,))
            logw = data.log_weight - (beta - .7) * 8 * 22 ** 2 * epsilon
            w = np.exp(logw - logw.max())
            w /= w.sum()
            for name, key in (("Q_U", "q_u"), ("Q_z", "q_z"), ("Q_plaquette", "q_plaq")):
                self.assertAlmostEqual(values[f"{beta}/mean_{name}"], w @ charges[key])
                self.assertAlmostEqual(values[f"{beta}/mean_{name}_squared"], w @ charges[key] ** 2)

    def test_blocking_squares_before_averaging_and_drops_chain_tails(self):
        q = np.tile([1., -1.], 32)
        chains = [np.column_stack((q, 2 * q, .5 * q)) for _ in range(3)]
        chains[0] = np.vstack((chains[0], [999., 999., 999.]))
        estimate, error, count, dropped = blocked_charge_moments(chains, 2)
        np.testing.assert_allclose(estimate, [0, 1, 0, 4, 0, .25])
        np.testing.assert_allclose(error, 0)
        self.assertEqual(count, 96)
        self.assertEqual(dropped, [1, 0, 0])

    def test_final_cooling_alignment_burnin_and_all_three_charge_columns(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_mc(root)
            chains, info = load_mc_charges(root, 22, .7, 20)
            self.assertEqual(len(chains[0]), 62)
            np.testing.assert_allclose(chains[0][:, 1], 2 * chains[0][:, 0] + .2)
            self.assertEqual(info[0]["cooling_step"], 50)
            topo_path = root / "run_1/topo.dat"
            topo = np.loadtxt(topo_path)
            topo[1, 0] = 999
            np.savetxt(topo_path, topo)
            with self.assertRaisesRegex(ValueError, "Misaligned"):
                load_mc_charges(root, 22, .7, 20)

    def test_end_to_end_six_moments_and_new_output_directory(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            ns = make_ns(root / "ns")
            make_mc(root / "mc")
            output = root / "export"
            analyze(ns, root / "mc", output, 22, (.7, .7001), 40, 1500, .7,
                    bootstrap=3, seed=4, burn_in=20, block_size=2)
            with (output / "charge_moments.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 18)
            self.assertEqual({row["observable"] for row in rows}, set(QUANTITIES))
            self.assertTrue((output / "completed").is_file())
            meta = json.loads((output / "inputs.json").read_text())
            self.assertEqual(meta["NS_streams"], 2)
            with self.assertRaises(FileExistsError):
                analyze(ns, root / "mc", output, 22, (.7,), 40, 1500, .7,
                        bootstrap=3, seed=4, burn_in=20, block_size=2)

    def test_historical_scratch_mapping(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            expected = root / "group/job_123/run_0"
            expected.mkdir(parents=True)
            self.assertEqual(scratch_path("/rs_scratch/users/lb25v444/out_data/group/job_123/run_0", root), expected)

    def test_plot_prefers_complete_exports_and_ignores_incomplete_jobs(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            scan = root / "scan"
            scan.mkdir()
            (scan / "volume_comparison.csv").write_text(
                "method,L,target_beta,mean_Q_U,mean_Q_U_se\nNS,22,0.7,999,0.1\n")
            export = root / "N4_L22_res/charge_moments/job_123"
            export.mkdir(parents=True)
            rows = [{"method": method, "L": 22, "beta": .7, "observable": key,
                     "estimate": .5, "standard_error": .1}
                    for method in ("NS", "MCMC") for key in QUANTITIES]
            with (export / "charge_moments.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            (export / "inputs.json").write_text(json.dumps(
                {"L": 22, "cpn_n": 4, "source_beta": .7, "theta": 0., "targets": [.7], "MCMC_beta": .7}))
            with patch.multiple(plot_charge_moments, REPO=root, SCAN=scan, LARGE={}):
                points, _, _ = plot_charge_moments.load_charge_points()
                self.assertEqual(points[0]["estimate"], 999)
                (export / "completed").touch()
                points, _, _ = plot_charge_moments.load_charge_points()
                self.assertEqual(len(points), 12)
                self.assertEqual({p["observable"] for p in points}, set(QUANTITIES))
                self.assertTrue(all(p["estimate"] == .5 for p in points))
                plot_charge_moments.plot_charges(root / "figure")
                self.assertTrue((root / "figure/charge_moments.pdf").is_file())


if __name__ == "__main__":
    unittest.main()
