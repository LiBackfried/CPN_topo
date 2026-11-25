import csv
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

from N4_volume_benchmark import analyze_sampling_validation as study
from utils.mcmc import MCMCChain


def mc_fixture(root, count=4200, beta=.7, starts=(0, 0, 1, 1), cadence=1):
    chains = []
    for run, start in enumerate(starts):
        path = root / f"run_{run}"
        path.mkdir(parents=True)
        seed = 1001 + run
        (path / "input.conf").write_text(
            f"size 22 22\nbeta {beta}\ntheta 0\nrng_seed {seed}\nstart {start}\n"
            f"meas_every {cadence}\nnum_cool_step 50\nmeas_cool_every 50\n"
            "data_file dati.dat\ntopo_file topo.dat\n")
        (path / "log.dat").write_text("Theory: 2d CP^{N-1} model with N = 4\n")
        steps = cadence * np.arange(1, count + 1)
        rng = np.random.default_rng(seed)
        action = .65 + rng.uniform(-.05, .05, count)
        g0, gk, q = 10 + rng.normal(size=count), 4 + .2*rng.normal(size=count), rng.normal(size=count)
        np.savetxt(path / "dati.dat", np.column_stack((steps, action, g0, gk)))
        np.savetxt(path / "topo.dat", np.column_stack((steps, np.full(count, 50), q)))
        chains.append(MCMCChain(path, (22, 22), beta, 0., seed, cadence, 50, steps, action, g0, gk, q))
    return chains


class SamplingValidationTests(unittest.TestCase):
    def test_acf_matches_independent_and_ar1_series_and_flags_constant(self):
        rng = np.random.default_rng(512)
        white = rng.normal(size=100000)
        result, rho = study.autocorrelation(white)
        self.assertAlmostEqual(result['tau_int'], .5, delta=.06)
        self.assertTrue(result['reliable'])
        self.assertEqual(rho[0], 1.)
        ar = np.zeros_like(white)
        for i in range(1, len(ar)):
            ar[i] = .8*ar[i-1] + white[i]
        result, _ = study.autocorrelation(ar)
        self.assertAlmostEqual(result['tau_int'], 4.5, delta=.8)
        self.assertAlmostEqual(result['rho8'], .8**8, delta=.035)
        result, rho = study.autocorrelation(np.ones(200))
        self.assertIsNone(result['tau_int'])
        self.assertFalse(result['reliable'])
        self.assertIsNone(rho)
        for values in (np.arange(10), [np.nan]*50):
            with self.assertRaises(ValueError):
                study.autocorrelation(values)

    def test_source_full_analysis_preserves_cold_hot_and_live_point_timing(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            mc_fixture(root / 'mc')
            args = SimpleNamespace(mcmc=root/'mc', output=root/'source', lattice=22,
                                   cuts=[0,20,100,500,1000,2000], acf_burn=2000)
            study.analyze_source(args)
            self.assertTrue((args.output/'completed').exists())
            with (args.output/'live_spacing_windows.csv').open() as file:
                rows = list(csv.DictReader(file))
            initial = [r for r in rows if r['window'] == 'initial_20_8']
            self.assertEqual(len(initial), 20)
            self.assertEqual({(r['first_step'], r['last_step'], r['spacing']) for r in initial}, {('21','413','8')})
            with (args.output/'autocorrelation.csv').open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), 20)
            self.assertEqual({r['start'] for r in rows}, {'0', '1'})
            self.assertEqual({r['burn_in'] for r in rows}, {'2000'})
            for name in ['histories_early.png','histories_full.png','autocorrelation.png','cut_scan.csv','binning.csv']:
                self.assertGreater((args.output/name).stat().st_size, 0)
            config = root/'mc/run_0/input.conf'
            config.write_text(config.read_text().replace('start 0', 'start 1'))
            args.output = root/'rejected'
            with self.assertRaisesRegex(ValueError, 'two cold'):
                study.analyze_source(args)
            self.assertFalse(args.output.exists())

    def test_proposal_comparison_never_pools_different_kernels(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            mc_fixture(root/'mc', count=12288, beta=1., starts=(1,1,1), cadence=10)
            paths = []
            data = []
            for i in range(32):
                path = root/f'ns_{i}'
                path.mkdir()
                (path/'input.conf').write_text(f'rng_seed {i+1}\n')
                paths.append(path)
                rng = np.random.default_rng(i)
                epsilon = np.linspace(.8,.5,4001) + i*1e-7
                data.append(np.column_stack((epsilon,10+rng.normal(size=4001),
                                             4+.2*rng.normal(size=4001),rng.normal(size=4001),
                                             np.zeros((4001,2)))))
            cfg = dict(size=['22','22'], num_single_site_stoc_upd=['86400'], num_live_pts=['50'],
                       num_MC_step=['20'], meas_every=['8'], rng_seed=['1'])
            test_cfg = {**cfg, 'num_single_site_stoc_upd':['172800'], 'rng_seed':['25']}
            args = SimpleNamespace(baseline=[root/'base'],control=[root/'control'],mcmc=root/'mc',
                                   output=root/'proposals', lattice=22, updates=4000, depths=[3000,3500,4000],
                                   bootstrap=4,joint_draws=20,seed=123)
            with patch.object(study, 'load_ns_ensemble', side_effect=[(cfg,data[:24]),(test_cfg,data[24:])]), \
                 patch.object(study, 'discover_runs', return_value=paths), \
                 patch.object(study, 'bootstrap_nested_sampling', wraps=study.bootstrap_nested_sampling) as bootstrap:
                study.analyze_proposals(args)
            self.assertEqual([len(call.args[0]) for call in bootstrap.call_args_list], [24,8])
            for name in ['baseline24/joint.json','control8/joint.json','proposal_differences.csv','control_depth.csv','completed']:
                self.assertTrue((args.output/name).exists(), name)
            with (args.output/'control_depth.csv').open() as file:
                self.assertEqual({r['updates'] for r in csv.DictReader(file)}, {'3000','3500','4000'})
            args.output = root/'rejected'
            test_cfg['meas_every'] = ['16']
            with patch.object(study, 'load_ns_ensemble', side_effect=[(cfg,data[:24]),(test_cfg,data[24:])]):
                with self.assertRaisesRegex(ValueError, 'settings'):
                    study.analyze_proposals(args)
            self.assertFalse(args.output.exists())


if __name__ == '__main__':
    unittest.main()
