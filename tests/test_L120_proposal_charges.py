import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from N4_volume_benchmark import plot_L120_proposal_charges as plot


def export_fixture(output, extra_edges=False, changed_mc=False):
    output.mkdir(parents=True)
    count,proposals=(24,86400) if output.name=='baseline24' else (24 if output.name=='control24' else 8,172800)
    (output/'inputs.json').write_text(json.dumps(dict(L=120,cpn_n=4,source_beta=.7,theta=0,
        targets=[1.],updates=300000,NS_streams=count,proposals=proposals,cooling_step=50,
        MCMC_beta=1.,burn_in_MC_steps=20000,block_size_measurements=512)))
    rows = []
    centers = [-2,-1,0,1,2] if extra_edges else [-1,0,1]
    for charge in plot.LABELS:
        for method in ('NS','MCMC'):
            for i,center in enumerate(centers):
                p = {0:.6,-1:.2,1:.2}.get(center,0.)
                if changed_mc and method=='MCMC':
                    p += .1 if center==0 else -.1 if center==1 else 0
                rows.append(dict(method=method,L=120,beta=1.,charge=charge,bin_index=i,
                    bin_left=center-.5,bin_right=center+.5,bin_center=center,
                    probability=p,standard_error=.01 if p else 0.))
    with (output/'charge_distributions.csv').open('w',newline='') as file:
        writer=csv.DictWriter(file,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)


class ProposalChargeTests(unittest.TestCase):
    def test_overlay_accepts_extra_empty_tail_bins_and_exports_all_charges(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp)
            export_fixture(root/'baseline24')
            export_fixture(root/'control8',extra_edges=True)
            plot.render(root,root/'comparison')
            for charge in plot.LABELS:
                for suffix in ('png','pdf'):
                    self.assertGreater((root/f'comparison/L120_{charge}_proposal_comparison.{suffix}').stat().st_size,0)
            inputs=json.loads((root/'comparison/plot_inputs.json').read_text())
            self.assertEqual(set(inputs),{'baseline24','control8'})

    def test_overlay_rejects_different_mcmc_reference(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp)
            export_fixture(root/'baseline24')
            export_fixture(root/'control8',changed_mc=True)
            with self.assertRaisesRegex(ValueError,'same MCMC'):
                plot.render(root,root/'rejected')

    def test_export_routes_distinct_proposals_to_separate_weighted_ensembles(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp); scratch=root/'out_data'
            groups=[]
            for group in range(12):
                job=scratch/f'ns/job_{group}'; groups.append(job)
                for run in range(4):
                    path=job/f'run_{run}'; path.mkdir(parents=True)
                    (path/'dati.dat').touch()
                    proposals=86400 if group<6 else 172800
                    (path/'input.conf').write_text(f'size 120 120\nbeta 0.7\ntheta 0\nnum_live_pts 50\n'
                        f'num_MC_step 20\nmeas_every 8\nnum_single_site_stoc_upd {proposals}\nrng_seed {4*group+run+1}\n')
            mc=scratch/'mc'
            for run in range(3):
                path=mc/f'run_{run}'; path.mkdir(parents=True)
                (path/'dati.dat').touch(); (path/'input.conf').write_text(f'rng_seed {100+run}\n')
            manifest=root/'inputs.json'
            manifest.write_text(json.dumps(dict(updates=300000,baseline=[p.as_posix() for p in groups[:6]],
                control=[p.as_posix() for p in groups[6:]],mcmc=mc.as_posix())))
            args=SimpleNamespace(output=root/'export',comparison=manifest,scratch_root=scratch,bootstrap=3,seed=123)
            def export(*args,**kw):
                export_fixture(args[2])
            with patch.object(plot,'analyze_distributions',side_effect=export) as analyze:
                plot.analyze(args)
            self.assertEqual([c.args[6] for c in analyze.call_args_list],[86400,172800])
            self.assertEqual([len(c.args[0]) for c in analyze.call_args_list],[6,6])
            for call in analyze.call_args_list:
                self.assertEqual(call.args[1],mc)
                self.assertEqual(call.args[3:6],(120,(1.,),300000))
                self.assertEqual(call.kwargs['burn_in'],20000)
                self.assertEqual(call.kwargs['block_size'],512)
            self.assertTrue((args.output/'completed').exists())
            bad=groups[-1]/'run_0/input.conf'
            bad.write_text(bad.read_text().replace('num_MC_step 20','num_MC_step 200'))
            args.output=root/'rejected'
            with self.assertRaisesRegex(ValueError,'Unexpected NS settings'):
                plot.analyze(args)
            self.assertFalse(args.output.exists())


if __name__=='__main__':
    unittest.main()
