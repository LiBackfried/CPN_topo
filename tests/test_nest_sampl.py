import unittest

import numpy as np

from analyze_nested_sampling import evaluate_at_beta, quantities
from utils.nest_sampl import CombinedNestedSampling, NestedSamplingStream
from utils.nest_sampl import combine_streams, reweight_beta


def combined_data(log_weights: np.ndarray, observables: dict[str, np.ndarray]
                  ) -> CombinedNestedSampling:
    size = len(log_weights)
    return CombinedNestedSampling(
        energy=np.arange(size, dtype=float),
        observables=observables,
        log_x=-np.arange(1, size + 1, dtype=float),
        log_weight=log_weights,
        log_weight_normalized=log_weights,
        log_z=0.0,
        log_z_curve=np.logaddexp.accumulate(log_weights),
        n_live_effective=1,
    )


class CombinedNestedSamplingTests(unittest.TestCase):
    def test_weighted_sum_avoids_intermediate_underflow(self) -> None:
        data = combined_data(
            np.array([-800.0, 0.0]),
            {"observable": np.array([1.0e300, 0.0])},
        )

        direct_sum = np.sum(data.weight * data.observables["observable"])
        expected = np.exp(-800.0 + np.log(1.0e300))

        self.assertEqual(direct_sum, 0.0)
        self.assertAlmostEqual(data.mean("observable") / expected, 1.0, places=13)
        self.assertAlmostEqual(data.log_mean("observable"), np.log(expected), places=13)

    def test_weighted_sum_supports_signed_observables(self) -> None:
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {"observable": np.array([1.0, -0.5])},
        )

        self.assertAlmostEqual(data.mean("observable"), 0.25)
        with self.assertRaisesRegex(ValueError, "non-negative"):
            data.log_mean("observable")

    def test_log_mean_of_zero_observable_is_negative_infinity(self) -> None:
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {"observable": np.zeros(2)},
        )

        self.assertEqual(data.mean("observable"), 0.0)
        self.assertEqual(data.log_mean("observable"), -np.inf)

    def test_variance_uses_centered_observations(self) -> None:
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {"observable": np.array([1.0e12 - 1.0, 1.0e12 + 1.0])},
        )

        self.assertAlmostEqual(data.mean("observable"), 1.0e12)
        self.assertAlmostEqual(data.variance("observable"), 1.0)

    def test_topological_susceptibility_uses_centered_variance(self) -> None:
        charge = np.array([1.0e12 - 1.0, 1.0e12 + 1.0])
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {
                "action_density": np.ones(2),
                "energy": np.ones(2),
                "g0": np.full(2, 2.0),
                "gk": np.ones(2),
                "q_u": charge,
                "q_z": charge,
                "q_plaq": charge,
            },
        )

        result = quantities(data, lattice_size=10)

        self.assertAlmostEqual(result["chi_topological"], 0.01)

    def test_expm1_keeps_tiny_shrinkage_weight_finite(self) -> None:
        stream = NestedSamplingStream(
            energy=np.array([1.0]),
            observables={"observable": np.array([1.0])},
            n_live=10**18,
        )

        data = combine_streams([stream])

        self.assertTrue(np.isfinite(data.log_weight[0]))
        self.assertAlmostEqual(data.log_weight[0], np.log(1.0e-18), places=13)

    def test_beta_reweighting_uses_extensive_energy(self) -> None:
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {"action_density": np.array([0.0, 1.0])},
        )
        delta_beta = np.log(2.0) / 2.0

        reweighted, log_z_ratio, quadrature_ess = reweight_beta(
            data,
            source_beta=0.7,
            target_beta=0.7 + delta_beta,
            cpn_n=1,
            volume=1,
        )

        np.testing.assert_allclose(reweighted.weight, np.array([2.0 / 3.0, 1.0 / 3.0]))
        self.assertAlmostEqual(log_z_ratio, np.log(0.75))
        self.assertAlmostEqual(quadrature_ess, 1.8)
        self.assertAlmostEqual(reweighted.log_z_curve[-1], 0.0)

    def test_quantities_report_extensive_energy_and_action(self) -> None:
        charge = np.zeros(2)
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {
                "action_density": np.array([0.0, 1.0]),
                "energy": np.array([0.0, 2.0]),
                "g0": np.full(2, 2.0),
                "gk": np.ones(2),
                "q_u": charge,
                "q_z": charge,
                "q_plaq": charge,
            },
        )

        result = quantities(data, lattice_size=2, cpn_n=4, beta=0.7)

        self.assertAlmostEqual(result["mean_extensive_energy"], 16.0)
        self.assertAlmostEqual(result["mean_symanzik_action"], 11.2)

    def test_evaluate_at_beta_keeps_prior_mass_separate_from_z_ratio(self) -> None:
        charge = np.zeros(2)
        data = combined_data(
            np.log(np.array([0.5, 0.5])),
            {
                "action_density": np.array([0.0, 1.0]),
                "energy": np.array([0.0, 2.0]),
                "g0": np.full(2, 2.0),
                "gk": np.ones(2),
                "q_u": charge,
                "q_z": charge,
                "q_plaq": charge,
            },
        )
        data = CombinedNestedSampling(**{**data.__dict__, "log_z": -0.125})

        _, result = evaluate_at_beta(
            data,
            lattice_size=1,
            source_beta=0.7,
            target_beta=0.7 + np.log(2.0) / 2.0,
            cpn_n=1,
        )

        self.assertEqual(result["log_accumulated_prior_mass"], -0.125)
        self.assertEqual(result["log_Z"], -0.125)
        self.assertEqual(result["log_remaining_prior_mass"], -2.0)
        self.assertAlmostEqual(result["remaining_prior_mass"], np.exp(-2.0))
        self.assertAlmostEqual(result["log_Z_ratio"], np.log(0.75))

    def test_accumulated_and_remaining_prior_mass_sum_to_one(self) -> None:
        stream = NestedSamplingStream(
            energy=np.arange(5.0),
            observables={"observable": np.ones(5)},
            n_live=2,
        )

        data = combine_streams([stream])

        self.assertAlmostEqual(
            np.logaddexp(data.log_z, data.log_x[-1]),
            0.0,
            places=15,
        )


if __name__ == "__main__":
    unittest.main()
