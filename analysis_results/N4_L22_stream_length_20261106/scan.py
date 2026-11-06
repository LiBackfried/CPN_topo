"""Paired stream-prefix test on the local N=4, L=22 UBELIX runs."""

import csv
import json
import re
import sys
from itertools import islice
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO))
from analyze_nested_sampling import evaluate_at_beta, read_config
from utils.nest_sampl import NestedSamplingStream, combine_streams

DATA = REPO.parent / 'data_N4_UBELIX'
BETAS = np.array([0.68, 0.69, 0.70, 0.71, 0.75])
KEYS = ('mean_action_density', 'xi_L_squared', 'xi_L', 'chi_topological', 'mean_Q_U', 'log_Z_ratio')
DEPTHS = [25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300,
          350, 400, 425, 450, 500, 600, 650, 750, 1000, 1250, 1400,
          1500, 1750, 2000, 2500, 5000, 10000]
FULL = 50000
BOOTSTRAP = 1000
SEED = 20261106
REFERENCE_JOBS = (21098598, 21098603, 21042450, 21098616, 21098620)
DELTA_LOG_FACTOR = -(BETAS - 0.7) * (2 * 4 * 22**2)
TOLERANCE = 0.1


def load_streams():
    streams, timings, seeds = [], [], []
    for run_id in range(750, 775):
        path = DATA / f'run_{run_id}'
        config = read_config(path / 'input.conf')
        expected = {'size': ['22', '22'], 'beta': ['0.7'], 'theta': ['0.0'],
                    'num_live_pts': ['50'], 'num_ns_meas': ['50001'],
                    'num_single_site_stoc_upd': ['1500'], 'start': ['1'],
                    'rng_start': ['0'], 'num_cool_step': ['50'], 'meas_cool_every': ['5']}
        for key, value in expected.items():
            assert config[key] == value, (path, key, config[key])
        seeds.append(int(config['rng_seed'][0]))
        log = (path / 'log.dat').read_text()
        assert 'model with N = 4' in log
        timings.append(float(re.search(r'^Simulation time:\s+([\d.]+)', log, re.M)[1]))
        general = np.loadtxt(path / 'dati.dat')
        with (path / 'topo.dat').open() as f:
            assert next(f).startswith('#')
            topo = np.loadtxt(islice(f, 10, None, 11), usecols=(0, 1, 2, 3, 4))
        acc = np.loadtxt(path / 'acceptance_rate.dat', usecols=(0,), dtype=int)
        assert len(general) == len(topo) == FULL + 1, path
        np.testing.assert_array_equal(acc, np.arange(1, FULL + 1))
        np.testing.assert_array_equal(general[:, 0], topo[:, 0])
        assert np.all(topo[:, 1] == 50) and np.all(np.isfinite(topo))
        assert np.all(np.isfinite(general)) and np.all(np.diff(general[:, 1]) <= 1e-14)
        eps = general[:, 1]
        obs = dict(action_density=eps, energy=2 * eps, g0=general[:, 2],
                   gk=general[:, 3], q_u=topo[:, 2], q_z=topo[:, 3], q_plaq=topo[:, 4])
        streams.append(NestedSamplingStream(2 * eps, obs, 50, path.name))
    assert len(set(seeds)) == 25 and min(seeds) > 0
    return streams, timings, seeds


def prefix(stream, updates):
    end = updates + 1
    return NestedSamplingStream(stream.energy[:end],
                                {k: v[:end] for k, v in stream.observables.items()},
                                stream.n_live, stream.name)


def repo_estimate(streams):
    merged = combine_streams(streams)
    estimates = [evaluate_at_beta(merged, 22, 0.7, beta if beta != 0.7 else None, 4)[1]
                 for beta in BETAS]
    return np.array([[x.get(key, 0.0) for key in KEYS] for x in estimates])


def prepare(streams, updates):
    fields = ('action_density', 'g0', 'gk', 'q_u')
    cols = np.vstack([np.column_stack([s.observables[k][:updates + 1] for k in fields])
                      for s in streams])
    order = np.argsort(cols[:, 0], kind='stable')[::-1]
    cols = cols[order]
    ids = order // (updates + 1)
    # Multiplicity compression requires equal-energy rows of the same stream
    # to have equal observables, and no energy ties across different streams.
    ties = np.flatnonzero(cols[:-1, 0] == cols[1:, 0])
    assert np.all(ids[ties] == ids[ties + 1])
    np.testing.assert_allclose(cols[ties], cols[ties + 1], atol=1e-10, rtol=1e-10)
    # Shift the beta factor for numerical conditioning. Restore it for log Z.
    factors = np.exp(DELTA_LOG_FACTOR[:, None] * (cols[:, 0] - 0.85))
    return cols, ids, factors


def estimate(prepared, counts):
    cols, ids, factors = prepared
    count = counts[ids]
    log_t = -1 / (50 * counts.sum())
    rank_before = np.cumsum(count) - count
    # Sum the geometric weights of repeated dead points as a single weight.
    mass = np.exp(log_t * rank_before) * -np.expm1(log_t * count)
    weight = factors * mass
    total = np.sum(weight, axis=1)
    eps, g0, gk, q = (np.einsum('ij,jk->ik', weight, cols) / total[:, None]).T
    xi2 = (g0 / gk - 1) / (4 * np.sin(np.pi / 22)**2)
    xi = np.sqrt(np.where(xi2 >= 0, xi2, np.nan))
    chi = np.sum(weight * (cols[:, 3] - q[:, None])**2, axis=1) / (total * 22**2)
    log_ratio = np.log(total) + DELTA_LOG_FACTOR * 0.85
    log_ratio[BETAS == 0.7] = 0.0
    return np.column_stack([eps, xi2, xi, chi, q, log_ratio])


def tail_mass_bound(streams, updates):
    # All discarded points have action at most this threshold. Count points
    # strictly above it in each stream, including the least favorable stream.
    threshold = max(np.max(s.observables['action_density'][updates + 1:]) for s in streams)
    above = min(np.count_nonzero(s.observables['action_density'][:updates + 1] > threshold)
                for s in streams)
    all_eps = np.concatenate([s.observables['action_density'] for s in streams])
    # The first 'above' / 50 units of -log X carry exactly the same data and
    # weights in both estimates. Bound all later mass for any bootstrap draw.
    tail_source = np.exp(-above / 50)
    spans = abs(DELTA_LOG_FACTOR) * np.ptp(all_eps)
    return above, tail_source * np.exp(spans) / (1 - tail_source)


def plot_scan(worst_errors):
    fig, ax = plt.subplots(figsize=(8.2, 4.6), layout='constrained')
    depths = np.array(DEPTHS)
    colors = ['#0072B2', '#009E73', '#555555', '#D55E00', '#CC79A7']
    for i, (beta, color) in enumerate(zip(BETAS, colors)):
        ratios = worst_errors[:, i]
        visible = (ratios > 0) & (depths <= 2500)
        ax.plot(depths[visible], ratios[visible], 'o-', ms=3, lw=1.4, color=color,
                label=f'{beta:.2f}' + (' (source)' if beta == 0.7 else ''))
    ax.axhline(TOLERANCE, ls='--', color='#666666', lw=1)
    ax.text(24, TOLERANCE * 1.25, '10% of 800-stream SE', color='#444444', fontsize=9)
    ax.set(xscale='log', yscale='log', xlim=(22, 2700), ylim=(1e-5, 1200),
           xlabel='Nested-sampling updates per stream',
           ylabel='Largest 95th-percentile absolute shift\n(in units of the 800-stream standard error)',
           title=r'Stream-length test for CP$^3$ on a $22\times22$ lattice')
    ticks = [25, 50, 100, 200, 450, 650, 1000, 1500, 2500]
    ax.set_xticks(ticks, [f'{n:,}' for n in ticks])
    ax.grid(axis='y', alpha=0.2)
    ax.legend(title=r'Target $\beta$', loc='upper right', frameon=False)
    fig.savefig(HERE / 'prefix_convergence.png', dpi=200)
    plt.close(fig)


def main():
    streams, timings, seeds = load_streams()
    print(f'Loaded {len(streams)} complete streams, {FULL} updates each', flush=True)
    reference = repo_estimate(streams)
    # Confirm alignment with the current CLI's convention, which trims the last
    # measurement when acceptance_rate.dat is one row shorter than dati.dat.
    np.testing.assert_allclose(repo_estimate([prefix(s, FULL - 1) for s in streams]),
                               reference, atol=5e-13, rtol=5e-13)
    production_errors = []
    for beta, job in zip(BETAS, REFERENCE_JOBS):
        folder = REPO / 'analysis_results/ns_constraint_22_N4_beta0p7_800x50000_stoc1500'
        result = json.loads((folder / f'job_{job}' / 'results.json').read_text())
        assert len(result['runs']) == 800 and result['settings']['target_beta'] == beta
        errors = result['bootstrap_standard_errors']
        production_errors.append([errors.get(key, 0.0) for key in KEYS])
    production_errors = np.array(production_errors)
    rng = np.random.default_rng(SEED)
    draws = rng.integers(0, len(streams), size=(BOOTSTRAP, len(streams)))
    counts = np.array([np.bincount(draw, minlength=len(streams)) for draw in draws])
    all_once = np.ones(len(streams), dtype=int)
    ref_cap = DEPTHS[-1]
    above, bound = tail_mass_bound(streams, ref_cap)
    print(f'Bootstrap reference cap {ref_cap}, common rank >= {above}/stream, bound {bound}', flush=True)
    assert np.max(bound) < 1e-14
    prepared = prepare(streams, ref_cap)
    np.testing.assert_allclose(estimate(prepared, all_once), reference, atol=5e-13, rtol=5e-13)
    for draw, count in zip(draws[:4], counts[:4]):
        check = repo_estimate([streams[i] for i in draw])
        np.testing.assert_allclose(estimate(prepared, count), check, atol=5e-13, rtol=5e-13)
    ref_samples = np.array([estimate(prepared, count) for count in counts])
    ref_errors = np.nanstd(ref_samples, axis=0, ddof=1)
    fields = ['updates', 'beta', 'observable', 'estimate', 'bootstrap_se', 'undefined_fraction',
              'full_estimate', 'full_bootstrap_se', 'full_undefined_fraction', 'newly_undefined_fraction',
              'paired_shift', 'paired_shift_se', 'paired_shift_p025',
              'paired_shift_p975', 'production_800_bootstrap_se', 'paired_abs_shift_p95',
              'paired_abs_shift_p95_over_full_se', 'paired_abs_shift_p95_over_800_se']
    worst_errors = np.zeros((len(DEPTHS) + 1, len(BETAS)))
    passes = np.ones_like(worst_errors, dtype=bool)
    with (HERE / 'prefix_scan.csv').open('w', newline='') as f:
        out = csv.writer(f)
        out.writerow(fields)
        for depth_idx, depth in enumerate([*DEPTHS, FULL]):
            if depth in (ref_cap, FULL):
                point = reference
                samples = ref_samples
            else:
                prepared = prepare(streams, depth)
                point = estimate(prepared, all_once)
                np.testing.assert_allclose(point, repo_estimate([prefix(s, depth) for s in streams]),
                                           atol=5e-13, rtol=5e-13)
                samples = np.array([estimate(prepared, count) for count in counts])
            for i, beta in enumerate(BETAS):
                for j, key in enumerate(KEYS):
                    if beta == 0.7 and key == 'log_Z_ratio':
                        continue
                    values = samples[:, i, j]
                    valid = np.isfinite(values)
                    valid_reference = np.isfinite(ref_samples[:, i, j])
                    paired = valid & valid_reference
                    newly_undefined = np.mean(valid_reference & ~valid)
                    diffs = values[paired] - ref_samples[paired, i, j]
                    error = np.std(values[valid], ddof=1) if valid.sum() > 1 else np.nan
                    shift_error = np.std(diffs, ddof=1) if paired.sum() > 1 else np.nan
                    lo, hi = np.quantile(diffs, [0.025, 0.975]) if len(diffs) else (np.nan, np.nan)
                    p95_abs = np.quantile(np.abs(diffs), 0.95) if len(diffs) else np.nan
                    ratio = p95_abs / production_errors[i, j]
                    worst_errors[depth_idx, i] = np.fmax(worst_errors[depth_idx, i], ratio)
                    passes[depth_idx, i] &= bool(newly_undefined == 0 and ratio <= TOLERANCE)
                    out.writerow([depth, f'{beta:.2f}', key, point[i, j], error, 1 - valid.mean(),
                                  reference[i, j], ref_errors[i, j], 1 - valid_reference.mean(),
                                  newly_undefined, point[i, j] - reference[i, j],
                                  shift_error, lo, hi, production_errors[i, j], p95_abs,
                                  p95_abs / ref_errors[i, j], ratio])
            print(f'{depth:5d} updates', flush=True)
            f.flush()
    first_passing = {str(beta): [*DEPTHS, FULL][np.flatnonzero(
        np.logical_and.accumulate(passes[::-1, i])[::-1])[0]] for i, beta in enumerate(BETAS)}
    meta = dict(seeds=seeds, run_ids=list(range(750, 775)), bootstrap_draws=BOOTSTRAP,
                rng_seed=SEED, reference_updates=FULL, bootstrap_reference_cap=ref_cap,
                bootstrap_cap_upper_bound_by_beta=dict(zip(map(str, BETAS), bound)),
                full_sim_cpu_seconds=timings, source_beta=0.7, fixed_theta=0,
                cooling_step=50, reference_800_job_ids=dict(zip(map(str, BETAS), REFERENCE_JOBS)),
                tolerance_in_production_se=TOLERANCE, first_passing_updates=first_passing)
    (HERE / 'scan_metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
    plot_scan(worst_errors[:-1])
    print(f'First passing updates by beta: {first_passing}', flush=True)


if __name__ == '__main__':
    main()
