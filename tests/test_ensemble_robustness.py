import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest

import numpy as np

from N4_volume_benchmark.check_ensemble_robustness import (
    block_bootstrap_totals, joint_diagnostics, run,
)
from N4_volume_benchmark.scan_depth import common_prefix, load_ns_ensemble
from analyze_nested_sampling import evaluate_at_beta
from utils.nest_sampl import combine_streams
from test_volume_beta_scan import make_mc, make_ns


class EnsembleRobustnessTests(unittest.TestCase):
    def test_joint_covariance_preserves_perfect_bin_correlation(self):
        ns = np.repeat(np.array([-1., 0., 1.])[:, None], 2, axis=1)
        mc = np.repeat(np.array([-2., -1., 1., 2.])[:, None], 2, axis=1)
        mc_boot = np.repeat(np.array([-1., 0., 1., 0.])[:, None], 2, axis=1)
        result, covariance, error = joint_diagnostics(
            np.ones(2), ns, mc, mc_boot, np.random.default_rng(5))
        # NS sample variance 1 plus MC jackknife variance 3*2.5.
        np.testing.assert_allclose(covariance, np.full((2, 2), 8.5))
        np.testing.assert_allclose(error, np.sqrt(8.5))
        self.assertAlmostEqual(result["max_abs_z"], 1 / np.sqrt(8.5))
        self.assertGreaterEqual(result["joint_bootstrap_p"], 1 / 5)
        # A rank-one covariance is valid: the diagnostic never inverts it.
        self.assertEqual(np.linalg.matrix_rank(covariance), 1)

    def test_joint_null_adds_the_signed_ns_and_mc_residual_variations(self):
        ns = np.array([[0., 0.], [1., 2.], [10., 3.]])
        mc = np.array([[0., 1.], [1., 3.], [3., 8.]])
        mc_boot = np.array([[0., 0.], [2., 5.], [3., 10.], [15., 20.]])
        result, _, error = joint_diagnostics(np.ones(2), ns, mc, mc_boot, np.random.default_rng(17))
        indices = np.random.default_rng(17).integers(0, len(ns), len(mc_boot))
        null = (ns - ns.mean(axis=0))[indices] + mc_boot - mc_boot.mean(axis=0)
        expected = np.quantile(np.max(np.abs(null / error), axis=1), .95)
        self.assertAlmostEqual(result["simultaneous_95_critical_z"], expected)

    def test_block_bootstrap_keeps_multivariate_blocks_intact(self):
        blocks = np.zeros((4, 4, 3))
        blocks[:, :, 0] = 5
        blocks[:, :, 1] = np.arange(4)[:, None]
        blocks[:, :, 2] = 2 * blocks[:, :, 1]
        samples = block_bootstrap_totals(blocks, 77, np.random.default_rng(123))
        np.testing.assert_allclose(samples[:, :, 0], 20)
        np.testing.assert_allclose(samples[:, :, 2], 2 * samples[:, :, 1])
        np.testing.assert_array_equal(samples, block_bootstrap_totals(blocks, 77, np.random.default_rng(123)))
        self.assertGreater(np.std(samples[:, 0, 1]), 0)

    def test_end_to_end_groups_and_leave_one_out_use_recomputed_weights(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            groups = [root / f"group{i}" for i in range(3)]
            for index, group in enumerate(groups):
                make_ns(group, 22, 1500, seeds=range(4 * index + 1, 4 * index + 5))
            make_mc(root / "mc", 22, .7001)
            for path in (root / "mc").iterdir():
                data = np.loadtxt(path / "dati.dat")
                data[:, 1] = .65 + 7 * (data[:, 1] - .5)
                np.savetxt(path / "dati.dat", data)
            args = SimpleNamespace(ns=groups, mcmc=root / "mc", output=root / "checks",
                                   updates=40, beta=.7001, bins=[2, 4], blocks=[1, 2],
                                   baseline_bins=4, baseline_block=2, burn_in=0,
                                   tail=.05, bootstrap=6, joint_draws=20, seed=9)
            run(args)
            self.assertTrue((args.output / "completed").exists())
            inputs = json.loads((args.output / "inputs.json").read_text())
            self.assertEqual([len(group) for group in inputs["ns_groups"]], [4, 4, 4])
            with (args.output / "step1/grid.csv").open() as file:
                self.assertEqual(len(list(csv.DictReader(file))), 4)
            with (args.output / "step2/observables.csv").open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), (1 + 3 + 12) * 6)
            cfg, chains = load_ns_ensemble(groups)
            streams = common_prefix(chains, 40, int(cfg["num_live_pts"][0]))
            reduced = combine_streams(streams[1:])
            _, expected = evaluate_at_beta(reduced, 22, .7, .7001, 4)
            loo = {row["observable"]: row for row in rows if row["subset"] == "leave_out_0"}
            for key, row in loo.items():
                self.assertAlmostEqual(float(row["estimate"]), expected[key])
                self.assertEqual(row["bootstrap_se"], "")
            # Detect accidentally retaining 12-stream shrinkage after omitting one.
            full = combine_streams(streams)
            target, _ = evaluate_at_beta(full, 22, .7, .7001, 4)
            keep = full.observables["stream_index"] != 0
            naive = np.average(full.observables["action_density"][keep], weights=target.weight[keep])
            self.assertGreater(abs(naive - expected["mean_action_density"]), 1e-8)
            with (args.output / "step2/leave_one_out_bins.csv").open() as file:
                self.assertEqual(len(list(csv.DictReader(file))), 12 * 4 * 2)
            with (args.output / "step2/group_pairs.csv").open() as file:
                self.assertEqual(len(list(csv.DictReader(file))), 3 * (6 + 4 * 2))
            with self.assertRaisesRegex(ValueError, "overwrite"):
                run(args)


if __name__ == "__main__":
    unittest.main()
