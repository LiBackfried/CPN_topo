from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

import numpy as np

from utils.mcmc import MCMCChain, binning_analysis, block_means, load_ensemble


def make_chain(seed, q):
    q = np.asarray(q, dtype=float)
    return MCMCChain(Path(f"run_{seed}"), (38, 38), 1.0, 0.0, seed, 10, 50,
                     10 * np.arange(1, len(q) + 1), 0.5 + q / 10, 8 + q, 2 + q / 2, q)


class BinningTests(unittest.TestCase):
    def test_linear_error_matches_standard_error_of_bin_means(self):
        chain = make_chain(1, [1, 1, 0, 0, -1, -1, 0, 0])
        result = binning_analysis([chain], min_blocks=2)[1]
        expected = np.std(block_means(chain.action_density, 2), ddof=1) / 2
        self.assertEqual(result.block_size, 2)
        self.assertAlmostEqual(result.standard_error[0], expected)

    def test_pooled_jackknife_preserves_covariances_and_chain_boundaries(self):
        chains = [make_chain(1, [0, 1, 0, 2, 99]), make_chain(2, [1, 0, 2, 1, -99])]
        result = binning_analysis(chains, min_blocks=2)[1]
        data = np.concatenate([np.column_stack((c.q_u, c.g0, c.gk))[:4] for c in chains])

        def statistics(rows):
            q, g0, gk = rows.T
            xi_sq = (g0.mean() / gk.mean() - 1) / (4 * np.sin(np.pi / 38)**2)
            return [q.var() / 38**2, xi_sq]

        expected_samples = np.array([statistics(np.delete(data, [i, i + 1], axis=0))
                                     for i in range(0, 8, 2)])
        self.assertEqual(result.n_blocks, 4)
        np.testing.assert_allclose(result.estimate[3:], statistics(data))
        np.testing.assert_allclose(result.standard_error[3:], np.sqrt(3) * expected_samples.std(axis=0))

    def test_burn_in_uses_mc_step_and_includes_the_boundary_in_cut(self):
        retained = make_chain(1, [0, 1, 2]).after_burn_in(20)
        np.testing.assert_array_equal(retained.steps, [30])
        np.testing.assert_array_equal(retained.q_u, [2])


class LoadTests(unittest.TestCase):
    def test_load_last_recorded_cooling_step_and_detect_misalignment(self):
        with TemporaryDirectory() as tmp:
            parent = Path(tmp)
            chain = parent / "run_0"
            chain.mkdir()
            (chain / "input.conf").write_text(
                "size 38 38\nbeta 1.0\ntheta 0\nrng_seed 1\nmeas_every 10\n"
                "num_cool_step 7\nmeas_cool_every 5\ndata_file dati.dat\ntopo_file topo.dat\n",
                encoding="utf-8")
            (chain / "dati.dat").write_text("10 .5 2 1\n20 .6 2 1\n", encoding="utf-8")
            topo = chain / "topo.dat"
            topo.write_text("10 0 0\n10 5 1\n20 0 1\n20 5 2\n", encoding="utf-8")
            loaded, = load_ensemble(parent)
            self.assertEqual(loaded.cooling_step, 5)
            np.testing.assert_array_equal(loaded.q_u, [1, 2])
            topo.write_text("10 0 0\n10 5 1\n30 0 1\n30 5 2\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "does not match"):
                load_ensemble(parent)
