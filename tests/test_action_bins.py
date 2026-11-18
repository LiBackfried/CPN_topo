import unittest

import numpy as np

from N4_volume_benchmark.compare_action_bins import bin_totals, comparison, independent_errors


class ActionBinTests(unittest.TestCase):
    def test_mass_conditional_means_and_gap_decomposition(self):
        action = np.arange(4)
        edges = [0.5, 1.5, 2.5]
        ns = bin_totals(action, ([0, 2, 4, 8], [0, 3, 7, 8]), edges, np.array([1, 1, 3, 1]))
        mc = bin_totals(action, ([0, 1, 3, 9], [0, 3, 7, 9]), edges, np.array([1, 3, 1, 1]))
        bins, summary = comparison(ns, mc)
        np.testing.assert_allclose(bins["ns_mass"], [1/6, 3/6])
        np.testing.assert_allclose(bins["mcmc_mass"], [3/6, 1/6])
        np.testing.assert_allclose(bins["delta_G0"], [1, 1])
        np.testing.assert_allclose(summary["within_bin"], [1, 0])
        np.testing.assert_allclose(summary["bin_weight"], [1, 2])
        np.testing.assert_allclose(summary["full_difference"], [7/6, 7/6])
        np.testing.assert_allclose(summary["outside_range_effect"], [-5/6, -5/6])

    def test_resamples_hold_the_other_method_fixed(self):
        full = np.array([[1., 0., 0.], [2., 8., 12.], [3., 9., 18.], [1., 0., 0.]])
        changed = full.copy()
        changed[1, 1] += 4
        ns_bins, _ = comparison(np.stack((full, changed)), full)
        mc_bins, _ = comparison(full, np.stack((full, changed)))
        errors = independent_errors(ns_bins, mc_bins)
        np.testing.assert_allclose(errors["ns_G0"], [np.sqrt(2), 0])
        np.testing.assert_allclose(errors["mcmc_G0"], [1, 0])
        np.testing.assert_allclose(errors["delta_G0"], [np.sqrt(3), 0])

    def test_missing_conditional_bin_is_rejected(self):
        full = np.ones((4, 3))
        missing = full.copy()
        missing[1] = 0
        with self.assertRaisesRegex(ValueError, "Empty comparison bin"):
            comparison(missing, full)
