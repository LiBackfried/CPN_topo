import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

from N4_volume_benchmark import scan_stream_count as scan
from utils.nest_sampl import bootstrap_nested_sampling
from test_volume_beta_scan import make_mc, make_ns


class StreamCountTests(unittest.TestCase):
    def test_subset_paths_are_nested_without_replacement_and_reproducible(self):
        plan = scan.subset_plan(24, [6, 8, 12, 16, 20, 24], 8, 123)
        self.assertEqual(plan, scan.subset_plan(24, [6, 8, 12, 16, 20, 24], 8, 123))
        self.assertNotEqual(plan, scan.subset_plan(24, [6, 8, 12, 16, 20, 24], 8, 124))
        for row in plan:
            previous = set()
            for k, ids in row['subsets'].items():
                self.assertEqual(len(ids), int(k))
                self.assertEqual(len(set(ids)), int(k))
                self.assertTrue(previous.issubset(ids))
                previous = set(ids)
            self.assertNotIn('24', row['subsets'])
        with self.assertRaisesRegex(ValueError, 'include the full'):
            scan.subset_plan(24, [6, 12], 2, 1)

    def test_subset_scatter_is_distinct_from_bootstrap_precision(self):
        rows = [dict(streams=6, observable='a', estimate=1., bootstrap_se=2.),
                dict(streams=6, observable='a', estimate=3., bootstrap_se=4.),
                dict(streams=24, observable='a', estimate=2., bootstrap_se=1.)]
        result = scan.scaling_summary(rows, rows[-1:], 'estimate', 'bootstrap_se', ('observable',))
        self.assertAlmostEqual(result[0]['subset_estimate_sd'], np.sqrt(2))
        self.assertEqual(result[0]['ns_se_median'], 3.)
        self.assertEqual(result[0]['independent_scaling_reference'], 2.)
        self.assertEqual(result[1]['subset_estimate_sd'], 0.)
        self.assertEqual(result[1]['ns_se_median'], 1.)
        self.assertEqual(result[1]['subsets'], 1)

    def test_old_new_comparison_cancels_shared_mcmc_error(self):
        old = dict(observables=[dict(observable='G0', estimate=4., bootstrap_se=3., mcmc_se=100.)], bins=[])
        new = dict(observables=[dict(observable='G0', estimate=1., bootstrap_se=4., mcmc_se=100.)], bins=[])
        row = scan.old_new_differences(old, new)[0]
        self.assertEqual(row['old_minus_new'], 3.)
        self.assertEqual(row['independent_ns_se'], 5.)
        self.assertEqual(row['difference_over_se'], .6)

    def test_end_to_end_cache_control_groups_resume_and_collect(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            groups = [root / f'group{i}' for i in range(6)]
            for index, group in enumerate(groups):
                make_ns(group, 22, 1500, seeds=range(4 * index + 1, 4 * index + 5))
            make_mc(root / 'mc', 22, .7001)
            for index, path in enumerate(sorted((root / 'mc').iterdir())):
                config = path / 'input.conf'
                config.write_text(config.read_text().replace(f'rng_seed {index + 1}', f'rng_seed {1001 + index}'))
                data = np.loadtxt(path / 'dati.dat')
                data[:, 1] = .65 + 7 * (data[:, 1] - .5)
                np.savetxt(path / 'dati.dat', data)
            args = SimpleNamespace(ns=groups, mcmc=root / 'mc', output=root / 'cache',
                                   expected_lattice=22, expected_stoc=1500, updates=40, beta=.7001,
                                   burn_in=0, block_size=1, bins=2, focus_bin=1, tail=.05,
                                   counts=[6, 12, 24], orderings=2, bootstrap=4, joint_draws=20, seed=19)
            scan.prepare(args)
            settings, streams, edges, blocks = scan.load_cache(args.output)
            self.assertEqual(len(streams), 24)
            self.assertTrue((args.output / 'completed').exists())
            self.assertEqual([row['cohort'] for row in settings['streams'][:12]], ['old'] * 12)
            self.assertEqual([row['cohort'] for row in settings['streams'][12:]], ['new'] * 12)
            with self.assertRaisesRegex(ValueError, 'overwrite'):
                scan.prepare(args)
            evaluations = root / 'evaluations'
            task = SimpleNamespace(cache=args.output, task=0, output=evaluations / 'task_0')
            scan.evaluate(task)
            with patch.object(scan, 'bootstrap_nested_sampling', side_effect=AssertionError('must reuse')):
                scan.evaluate(task)
            for label in ['old12', 'new12', 'full24']:
                self.assertTrue((task.output / label / 'comparison/joint.json').exists())
            old = scan.read_json(task.output / 'old12/result.json')['selected']
            new = scan.read_json(task.output / 'new12/result.json')['selected']
            self.assertFalse(set(old) & set(new))
            self.assertEqual(sorted(old + new), list(range(24)))
            task = SimpleNamespace(cache=args.output, task=1, output=evaluations / 'task_1')
            calls = 0

            def fail_after_one(*pos, **kw):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise RuntimeError('simulated interrupted array task')
                return bootstrap_nested_sampling(*pos, **kw)

            with patch.object(scan, 'bootstrap_nested_sampling', side_effect=fail_after_one):
                with self.assertRaisesRegex(RuntimeError, 'interrupted'):
                    scan.evaluate(task)
            self.assertTrue((task.output / 'k6/result.json').exists())
            self.assertFalse((task.output / 'completed').exists())
            with patch.object(scan, 'bootstrap_nested_sampling', wraps=bootstrap_nested_sampling) as bootstrap:
                scan.evaluate(task)
                self.assertEqual(bootstrap.call_count, 1)
            scan.evaluate(SimpleNamespace(cache=args.output, task=2, output=evaluations / 'task_2'))
            report = SimpleNamespace(cache=args.output, evaluations=evaluations, output=root / 'report')
            scan.collect(report)
            self.assertTrue((report.output / 'completed').exists())
            with (report.output / 'subset_observables.csv').open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), 5 * 6)
            self.assertEqual(sum(row['streams'] == '24' for row in rows), 6)
            with (report.output / 'scaling_summary.csv').open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), 3 * 6)
            self.assertTrue(all(row['subsets'] == '1' and float(row['subset_estimate_sd']) == 0
                                for row in rows if row['streams'] == '24'))
            for name in ['error_scaling.png', 'estimate_scaling.png', 'focus_G0_scaling.png']:
                self.assertTrue((report.output / name).exists())
            with self.assertRaisesRegex(ValueError, 'overwrite'):
                scan.collect(report)
            with (args.output / 'stream_00.npy').open('ab') as file:
                file.write(b'changed')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                scan.load_cache(args.output)


if __name__ == '__main__':
    unittest.main()
