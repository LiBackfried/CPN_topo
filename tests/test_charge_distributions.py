import csv
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import numpy as np

from N4_volume_benchmark import plot_charge_distributions as distributions
from utils.nest_sampl import NestedSamplingStream, combine_streams


class ChargeDistributionTests(unittest.TestCase):
    def test_weighted_histograms_match_explicit_canonical_weights(self):
        epsilon = np.array([.8, .7, .6])
        charges = {"q_u": np.array([-1., 0., 2.]), "q_z": np.array([2., -3., 1.]),
                   "q_plaq": np.array([.2, -.7, 1.4])}
        streams = [NestedSamplingStream(2 * epsilon, {"action_density": epsilon, **charges}, 50)]
        edges = distributions.charge_edges(streams, [], .5)
        binned = combine_streams(distributions.histogram_streams(streams, edges))
        for beta in (.6999, .7, .7001):
            actual = distributions.ns_histogram_statistic(binned, 22, (beta,), edges)
            weights = np.exp(-np.arange(3) / 50) - np.exp(-np.arange(1, 4) / 50)
            exponent = -(beta - .7) * 8 * 22 ** 2 * epsilon
            weights *= np.exp(exponent - exponent.max())
            weights /= weights.sum()
            for name, key in distributions.CHARGES:
                expected = np.histogram(charges[key], edges[name], weights=weights)[0]
                computed = [actual[f"{beta}/{name}/{i}"] for i in range(len(expected))]
                np.testing.assert_allclose(computed, expected, atol=1e-14)

    def test_small_tail_bin_is_not_lost_by_cumulative_sum_cancellation(self):
        epsilon = np.linspace(.8, .5, 200)
        q = np.zeros(200)
        q[-1] = 1.
        stream = NestedSamplingStream(2 * epsilon,
                                      {"action_density": epsilon, "q_u": q, "q_z": q, "q_plaq": q}, 1)
        edges = distributions.charge_edges([stream], [])
        data = combine_streams(distributions.histogram_streams([stream], edges))
        values = distributions.ns_histogram_statistic(data, 22, (.7,), edges)
        expected = (np.exp(-199) - np.exp(-200)) / (1 - np.exp(-200))
        self.assertGreater(values["0.7/Q_U/1"], 0)
        self.assertAlmostEqual(values["0.7/Q_U/1"] / expected, 1., places=12)

    def test_mcmc_histogram_blocks_preserve_correlations_and_drop_each_tail(self):
        q = np.tile([1., -1.], 32)
        chains = [np.column_stack((q, 2 * q, .2 * q)) for _ in range(3)]
        chains[0] = np.vstack((chains[0], [999, 999, 999]))
        edges = {name: np.arange(-2.5, 3.5) for name, _ in distributions.CHARGES}
        estimate, error, blocks, dropped = distributions.mc_histograms(chains, edges, 2)
        np.testing.assert_allclose(estimate["Q_U"], [0, .5, 0, .5, 0])
        np.testing.assert_allclose(estimate["Q_z"], [.5, 0, 0, 0, .5])
        np.testing.assert_allclose(estimate["Q_plaquette"], [0, 0, 1, 0, 0])
        for value in error.values():
            np.testing.assert_allclose(value, 0)
        self.assertEqual(blocks, 96)
        self.assertEqual(dropped, [1, 0, 0])

    def test_edges_do_not_round_charges_and_keep_the_final_boundary(self):
        edges = np.array([-1.5, -.5, .5, 1.5])
        values = np.array([-.50001, -.5, .49999, .5, 1.5])
        np.testing.assert_array_equal(distributions.bin_indices(values, edges), [0, 1, 1, 2, 2])
        with self.assertRaisesRegex(ValueError, "every charge"):
            distributions.bin_indices(np.array([2.]), edges)

    def test_latest_l120_manifest_selects_twenty_four_leaves(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            scratch = root / "out_data"
            manifest = root / "analysis/inputs.tsv"
            manifest.parent.mkdir()
            records = ["kind\tjob_id\tdirectory"]
            for job in range(6):
                leaf = scratch / f"ns_N4_beta0p7_volume_benchmark/L120/job_{job}"
                for run in range(4):
                    path = leaf / f"run_{run}"
                    path.mkdir(parents=True)
                    (path / "dati.dat").touch()
                records.append(f"ns\t{job}\t/rs_scratch/users/test/out_data/ns_N4_beta0p7_volume_benchmark/L120/job_{job}")
            mc = scratch / "mcmc_120_N4_beta1p0_3x100k/job_22780263"
            mc.mkdir(parents=True)
            records.append("mcmc\t22780263\t/rs_scratch/users/test/out_data/mcmc_120_N4_beta1p0_3x100k/job_22780263")
            manifest.write_text("\n".join(records) + "\n")
            (manifest.parent / "completed").touch()
            with patch.object(distributions, "LATEST_L120", manifest):
                paths, mc_root, targets, updates, proposals, beta, selected = distributions.distribution_inputs(120, scratch)
            self.assertEqual(len(paths), 24)
            self.assertEqual(mc_root, mc)
            self.assertEqual(targets, (.9, .95, 1.))
            self.assertEqual((updates, proposals, beta, selected), (300000, 86400, 1., manifest))

    def test_end_to_end_export_normalization_and_replot(self):
        # Reuse the complete three-charge raw-file fixtures in the moment tests.
        from test_charge_moments import make_ns, make_mc
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            ns = make_ns(root / "ns")
            make_mc(root / "mc")
            output = root / "distributions"
            distributions.analyze_distributions(ns, root / "mc", output, 22, (.7, .7001),
                                                40, 1500, .7, bootstrap=3, burn_in=20, block_size=2)
            self.assertTrue((output / "completed").is_file())
            rows = distributions.read_histograms([output / "charge_distributions.csv"])
            groups = distributions.validate_histogram_rows(rows)
            self.assertEqual(len(groups), 9)
            self.assertTrue((output / "charge_distributions_beta0p7_log.pdf").is_file())
            ns_targets = {key[2] for key in groups if key[0] == "NS"}
            mc_targets = {key[2] for key in groups if key[0] == "MCMC"}
            self.assertEqual(ns_targets, {.7, .7001})
            self.assertEqual(mc_targets, {.7})
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                distributions.validate_histogram_rows(rows + rows[:1])
            altered = [dict(row) for row in rows]
            for row in altered:
                if row["method"] == "MCMC":
                    row["bin_left"] *= .5
                    row["bin_right"] *= .5
                    row["bin_center"] *= .5
            with self.assertRaisesRegex(ValueError, "same bin width"):
                distributions.validate_histogram_rows(altered)
            with self.assertRaises(FileExistsError):
                distributions.analyze_distributions(ns, root / "mc", output, 22, (.7,),
                                                    40, 1500, .7, bootstrap=3, burn_in=20, block_size=2)


if __name__ == "__main__":
    unittest.main()
