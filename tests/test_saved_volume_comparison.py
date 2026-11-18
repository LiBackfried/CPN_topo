import csv
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

import numpy as np

from N4_volume_benchmark.compare_saved_volumes import (
    add_correlation_length, difference, ns_from_summary, tables,
)


def saved_row(lattice, beta, depth=35000, xi_squared=9.0):
    row = {"L": lattice, "chains": 12, "updates": depth, "target_beta": beta,
           "last_tenth_target_mass": 0.0}
    for key, value in (("mean_action_density", 0.6), ("chi_topological", 0.001),
                       ("xi_L_squared", xi_squared), ("mean_G0", 10.0), ("mean_Gk", 5.0)):
        row[key] = value
        row[f"{key}_bootstrap_se"] = abs(value) / 10
    return row


def save_rows(path, rows):
    with path.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class SavedVolumeComparisonTests(unittest.TestCase):
    def test_sparse_scan_selects_deepest_without_filling_missing_betas(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "scan.csv"
            save_rows(path, [saved_row(38, 0.8, 30000), saved_row(38, 0.8, 35000),
                             saved_row(38, 1.0, 35000)])
            points = ns_from_summary(path, 38)
            self.assertEqual([r["target_beta"] for r in points], [0.8, 1.0])
            self.assertEqual(points[0]["updates"], 35000)
            self.assertAlmostEqual(points[0]["xi_L_se"], 0.9 / 6)
            self.assertAlmostEqual(points[0]["xi_L_over_L"], 3 / 38)
            with self.assertRaisesRegex(ValueError, "Expected L=66"):
                ns_from_summary(path, 66)

    def test_negative_xi_squared_is_preserved_and_sqrt_is_undefined(self):
        point = add_correlation_length({"L": 66, "xi_L_squared": -9.0, "xi_L_squared_se": 22.0})
        self.assertEqual(point["xi_L_squared"], -9.0)
        self.assertEqual(point["xi_status"], "unresolved")
        self.assertTrue(np.isnan(point["xi_L"]))
        self.assertTrue(np.isnan(point["xi_L_over_L_se"]))

    def test_tables_require_matching_volume_and_combine_independent_errors(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            rows = []
            for lattice in (22, 38, 66):
                path = root / f"L{lattice}.csv"
                save_rows(path, [saved_row(lattice, 0.9)])
                rows.extend(ns_from_summary(path, lattice))
            mc = {**rows[-1], "method": "MCMC", "mean_action_density": 0.5,
                  "mean_action_density_se": 0.08}
            rows.append(mc)
            refs = [{"L": "66", "beta": "0.9", "xi_L": "3.0", "xi_L_error": "0.1"},
                    {"L": "90", "beta": "0.9", "xi_L": "3.0", "xi_L_error": "0.1"}]
            shifts, matches = tables(rows, refs, root)
            self.assertEqual(len(shifts), 3 * 7)
            self.assertEqual(len(matches), 2)  # L90 is not a matched-volume reference.
            check = difference(rows[-2], mc, "mean_action_density")
            self.assertAlmostEqual(check["difference_se"], 0.1)
            self.assertAlmostEqual(check["difference_in_standard_errors"], 1.0)
            with (root / "availability.csv").open() as file:
                available = list(csv.DictReader(file))
            self.assertEqual(len(available), 21)
            self.assertEqual(sum(r["status"] == "available" for r in available), 3)

    def test_reject_duplicate_depth_and_wrong_proposals(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "scan.csv"
            row = saved_row(38, 0.8)
            save_rows(path, [row, row])
            with self.assertRaisesRegex(ValueError, "Duplicate beta/depth"):
                ns_from_summary(path, 38)
            row["stochastic_proposals"] = 4332
            save_rows(path, [row])
            with self.assertRaisesRegex(ValueError, "Unexpected proposal count"):
                ns_from_summary(path, 38)


if __name__ == "__main__":
    unittest.main()
