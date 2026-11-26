#!/usr/bin/env python3
"""Export and compare charge distributions of the two L120 proposal cohorts."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.export_charge_moments import scratch_path
from N4_volume_benchmark.plot_charge_distributions import analyze_distributions, read_histograms, LABELS
from utils.cpn_io import discover_runs, read_config

REPO = Path(__file__).resolve().parents[1]
COMPARISON = REPO / "N4_L120_res/proposals172800_23502237_analysis_23502241/inputs.json"
SOURCES = ("N4_volume_benchmark/plot_L120_proposal_charges.py",
           "N4_volume_benchmark/plot_charge_distributions.py",
           "N4_volume_benchmark/export_charge_moments.py", "N4_volume_benchmark/scan_depth.py",
           "analyze_nested_sampling.py", "utils/cpn_io.py", "utils/mcmc.py", "utils/nest_sampl.py")


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def histogram_vectors(rows):
    return {r['bin_center']:(r['probability'], r['standard_error']) for r in rows}


def render(root, output, floor=1e-6):
    if not 0 < floor < 1:
        raise ValueError("Probability floor must be between zero and one")
    cohorts = {name:read_histograms([root/name/"charge_distributions.csv"])
               for name in ("baseline24", "control8")}
    for name, rows in cohorts.items():
        metadata = json.loads((root/name/'inputs.json').read_text(encoding='utf-8'))
        count, proposals = (24,86400) if name=='baseline24' else (8,172800)
        expected = dict(L=120,cpn_n=4,source_beta=.7,theta=0,targets=[1.],updates=300000,
                        NS_streams=count,proposals=proposals,cooling_step=50,
                        MCMC_beta=1.,burn_in_MC_steps=20000,block_size_measurements=512)
        if any(metadata.get(key)!=value for key,value in expected.items()):
            raise ValueError(f'Unexpected histogram provenance: {name}')
        if {(r['L'],r['beta']) for r in rows} != {(120,1.)}:
            raise ValueError(f"Expected L120 beta=1 distributions: {name}")
        if {r['method'] for r in rows} != {'NS','MCMC'}:
            raise ValueError("Need NS and the shared MCMC reference in each export")
        if any(not np.isclose(r['bin_right']-r['bin_left'], 1.) or
                   not np.isclose(r['bin_center'], round(r['bin_center'])) for r in rows):
            raise ValueError("Use unit-width, integer-centered charge bins for this comparison")
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({'font.size':11, 'axes.spines.top':False, 'axes.spines.right':False, 'pdf.fonttype':42})
    for charge, label in LABELS.items():
        selected = {name:[r for r in rows if r['charge']==charge] for name,rows in cohorts.items()}
        mc = [histogram_vectors([r for r in rows if r['method']=='MCMC']) for rows in selected.values()]
        for center in set(mc[0]) | set(mc[1]):
            if not np.allclose(mc[0].get(center,(0.,0.)), mc[1].get(center,(0.,0.)), rtol=1e-9, atol=1e-12):
                raise ValueError("The two exports do not use the same MCMC histogram/errors")
        curves = [([r for r in selected['baseline24'] if r['method']=='NS'], 'NS: 86400 proposals, 24 streams', '#2369a4', 'o'),
                  ([r for r in selected['control8'] if r['method']=='NS'], 'NS: 172800 proposals, 8 streams', '#249c9a', '^'),
                  ([r for r in selected['baseline24'] if r['method']=='MCMC'], 'MCMC: beta=1, 3 chains', '#db7b18', 'D')]
        visible = [abs(r['bin_center']) for rows,_,_,_ in curves for r in rows if r['probability']>=floor]
        extent = max(visible, default=1.)+1
        fig, axes = plt.subplots(1,2,figsize=(12.5,5.5),constrained_layout=True)
        for ax, log in zip(axes,(False,True)):
            for rows,name,color,marker in curves:
                rows = sorted(rows,key=lambda r:r['bin_center'])
                x = np.array([r['bin_center'] for r in rows])
                p = np.array([r['probability'] for r in rows])
                se = np.array([r['standard_error'] for r in rows])
                keep = p>0 if log else np.ones(len(p),dtype=bool)
                ax.plot(x,np.where(keep,p,np.nan),color=color,alpha=.55,linewidth=1)
                ax.errorbar(x[keep],p[keep],yerr=se[keep],fmt=marker,mfc='none',color=color,
                            capsize=2,markersize=5,label=name)
            ax.set(xlabel=label,ylabel='Probability per unit-width bin',xlim=(-extent,extent))
            ax.grid(alpha=.18)
            if log:
                ax.set_yscale('log',nonpositive='mask'); ax.set_ylim(floor,1.)
            else:
                ax.set_ylim(bottom=0)
        axes[0].legend(fontsize=9)
        fig.suptitle(rf"CP$^3$: $L=120$, $\beta=1$, {label} after 50 cooling sweeps" +
                     "\nNS source beta=0.7; both proposal cohorts at 300000 updates/stream",fontsize=13)
        fig.supxlabel(f"NS: whole-stream bootstrap; MCMC: block jackknife. View covers bins with any P >= {floor:g}.\n"
                      "Measured charges are binned without rounding or symmetrizing; full normalized histograms are retained.",fontsize=9)
        for suffix in ('png','pdf'):
            fig.savefig(output/f"L120_{charge}_proposal_comparison.{suffix}",dpi=180)
        plt.close(fig)
    save_json(output/'plot_inputs.json', {name:{'path':str((root/name/'charge_distributions.csv').resolve()),
               'sha256':hashlib.sha256((root/name/'charge_distributions.csv').read_bytes()).hexdigest()}
               for name in cohorts})


def analyze(args):
    if args.output.exists():
        raise ValueError(f"Refusing to overwrite {args.output}")
    metadata = json.loads(args.comparison.read_text(encoding='utf-8'))
    if metadata['updates'] != 300000 or len(metadata['baseline']) != 6 or len(metadata['control']) != 2:
        raise ValueError("Expected the completed baseline24/control8 proposal comparison")
    roots = {name:[scratch_path(p,args.scratch_root) for p in metadata[key]]
             for name,key in (('baseline24','baseline'),('control8','control'))}
    mc = scratch_path(metadata['mcmc'],args.scratch_root)
    seeds = []
    for name,expected,proposals in (('baseline24',24,86400),('control8',8,172800)):
        paths = discover_runs(roots[name])
        if len(paths) != expected:
            raise ValueError(f"Expected {expected} streams: {name}")
        for path in paths:
            cfg = read_config(path/'input.conf')
            settings = (tuple(map(int,cfg['size'])),float(cfg['beta'][0]),float(cfg['theta'][0]),
                        *(int(cfg[k][0]) for k in ('num_live_pts','num_MC_step','meas_every','num_single_site_stoc_upd')))
            if settings != ((120,120),.7,0.,50,20,8,proposals):
                raise ValueError(f"Unexpected NS settings: {path}")
            seeds.append(int(cfg['rng_seed'][0]))
    if len(set(seeds)) != 32 or min(seeds)<=0:
        raise ValueError("Need 32 distinct positive NS seeds")
    for path in discover_runs([mc]):
        if int(read_config(path/'input.conf')['rng_seed'][0]) in seeds:
            raise ValueError("NS and MCMC seeds must be independent")
    args.output.mkdir(parents=True)
    save_json(args.output/'inputs.json',dict(comparison=str(args.comparison.resolve()),
        comparison_sha256=hashlib.sha256(args.comparison.read_bytes()).hexdigest(),
        bootstrap=args.bootstrap, seed=args.seed, beta=1., updates=300000,
        burn_in=20000, block_size=512, proposals=dict(baseline24=86400,control8=172800),
        source_hashes={p:hashlib.sha256((REPO/p).read_bytes()).hexdigest() for p in SOURCES}))
    for i,(name,proposals) in enumerate((('baseline24',86400),('control8',172800))):
        analyze_distributions(roots[name],mc,args.output/name,120,(1.,),300000,proposals,1.,
            bootstrap=args.bootstrap,seed=args.seed+i,burn_in=20000,block_size=512,
            bin_width=1.,manifest=args.comparison)
    render(args.output,args.output/'comparison')
    (args.output/'completed').write_text('Both proposal cohorts exported and charge distributions plotted.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode',required=True)
    run = sub.add_parser('analyze')
    run.add_argument('--comparison',type=Path,default=COMPARISON)
    run.add_argument('--scratch-root',type=Path,default=Path('/scratch/network/users/lb25v444/out_data'))
    run.add_argument('--output',type=Path,required=True)
    run.add_argument('--bootstrap',type=int,default=200)
    run.add_argument('--seed',type=int,default=20261126)
    plot = sub.add_parser('plot')
    plot.add_argument('root',type=Path)
    plot.add_argument('--output',type=Path)
    args = parser.parse_args()
    try:
        if args.mode=='analyze':
            if args.bootstrap<2 or args.seed<0:
                raise ValueError('Use at least two bootstraps and a nonnegative seed')
            analyze(args)
        else:
            render(args.root,args.output or args.root/'comparison')
    except (OSError,ValueError,KeyError) as exc:
        parser.error(str(exc))


if __name__=='__main__':
    main()
