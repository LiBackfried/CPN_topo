#!/usr/bin/env python3
"""Cache and analyze fixed-depth NS subsets, with disjoint old/new controls."""

from __future__ import annotations

import argparse
from functools import partial
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from N4_volume_benchmark.check_ensemble_robustness import (
    save_rows, statistic, unpack, write_comparison,
)
from N4_volume_benchmark.compare_action_bins import comparison, mcmc_block_totals
from N4_volume_benchmark.scan_depth import OBSERVABLES, STATISTICS, common_prefix, load_ns_ensemble
from utils.cpn_io import discover_runs, read_config
from utils.mcmc import OBSERVABLES as MC_OBSERVABLES, binning_analysis, load_ensemble
from utils.nest_sampl import NestedSamplingStream, bootstrap_nested_sampling


SCHEMA = 1
REPO = Path(__file__).resolve().parents[1]
SOURCES = ("N4_volume_benchmark/scan_stream_count.py", "N4_volume_benchmark/check_ensemble_robustness.py",
           "N4_volume_benchmark/compare_action_bins.py", "N4_volume_benchmark/scan_depth.py",
           "analyze_nested_sampling.py", "utils/nest_sampl.py", "utils/mcmc.py", "utils/cpn_io.py")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _digest(file)


def _digest(file):
    value = hashlib.sha256()
    for block in iter(lambda: file.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()


def subset_plan(total, counts, orderings, seed):
    if total < 4 or total % 2 or any(not 2 <= count <= total for count in counts):
        raise ValueError("Require an even stream total and counts between two and total")
    if len(set(counts)) != len(counts) or total not in counts or orderings < 1:
        raise ValueError("Counts must be distinct and include the full ensemble; use >=1 ordering")
    rng = np.random.default_rng(np.random.SeedSequence([seed, 11]))
    return [{"ordering": i, "permutation": (p := rng.permutation(total)).tolist(),
             "subsets": {str(k): sorted(p[:k].tolist()) for k in sorted(counts) if k < total}}
            for i in range(orderings)]


def prepare(args):
    if args.output.exists():
        raise ValueError(f"Refusing to overwrite cache: {args.output}")
    groups = [discover_runs([root]) for root in args.ns]
    paths = [p for group in groups for p in group]
    if len(groups) != 6 or any(len(group) != 4 for group in groups) or len(set(paths)) != 24:
        raise ValueError("Pass six disjoint leaf jobs with four streams each; old twelve first")
    config, data = load_ns_ensemble(paths)
    lattice, n_live = int(config["size"][0]), int(config["num_live_pts"][0])
    if lattice != args.expected_lattice or int(config["num_single_site_stoc_upd"][0]) != args.expected_stoc:
        raise ValueError("Unexpected lattice or stochastic proposals/update")
    if n_live != 50 or any(len(chain) - 1 != args.updates for chain in data):
        raise ValueError("Need 50 live points/stream and exactly the requested cumulative depth")
    plan = subset_plan(len(paths), args.counts, args.orderings, args.seed)
    chains = [chain.after_burn_in(args.burn_in) for chain in load_ensemble(args.mcmc)]
    if len(chains) != 3:
        raise ValueError("Expected three MCMC reference chains")
    identities = [dict(stream=i, cohort="old" if i < 12 else "new", path=str(path),
                       seed=int(read_config(path / "input.conf")["rng_seed"][0])) for i, path in enumerate(paths)]
    ns_seeds = {row["seed"] for row in identities}
    for chain in chains:
        if (chain.size, chain.beta, chain.theta) != ((lattice, lattice), args.beta, 0.):
            raise ValueError(f"MCMC target mismatch: {chain.path}")
        cfg = read_config(chain.path / "input.conf")
        if "Theory: 2d CP^{N-1} model with N = 4" not in (chain.path / cfg.get("log_file", ["log.dat"])[0]).read_text().splitlines():
            raise ValueError(f"Expected an N=4 MCMC log: {chain.path}")
        if chain.seed in ns_seeds or len(chain.steps) < 16 * args.block_size:
            raise ValueError("Need independent MCMC seeds and >=16 complete blocks per chain")
    actions = np.concatenate([c.action_density[:len(c.steps) // args.block_size * args.block_size] for c in chains])
    edges = np.quantile(actions, np.linspace(args.tail, 1 - args.tail, args.bins + 1))
    cutoff = max(chain[args.updates, 0] for chain in data)
    if np.any(np.diff(edges) <= 0) or cutoff >= edges[0]:
        raise ValueError("Repeated quantile edges or insufficient common NS support")
    streams = common_prefix(data, args.updates, n_live)
    args.output.mkdir(parents=True)
    for i, stream in enumerate(streams):
        np.save(args.output / f"stream_{i:02d}.npy", np.column_stack([stream.observables[k] for k in OBSERVABLES]))
    np.save(args.output / "edges.npy", edges)
    np.save(args.output / "blocks.npy", mcmc_block_totals(chains, args.block_size, edges))
    mc = next(row for row in binning_analysis(chains) if row.block_size == args.block_size)
    reference = {key: dict(estimate=float(value), se=float(error))
                 for key, value, error in zip(MC_OBSERVABLES, mc.estimate, mc.standard_error)}
    settings = dict(schema=SCHEMA, lattice=lattice, beta=args.beta, source_beta=.7, cpn_n=4,
                    updates=args.updates, n_live=n_live, stream_count=len(streams), bins=args.bins,
                    block_size=args.block_size, burn_in=args.burn_in, tail=args.tail,
                    bootstrap=args.bootstrap, joint_draws=args.joint_draws, seed=args.seed,
                    counts=sorted(args.counts), orderings=args.orderings, focus_bin=args.focus_bin,
                    common_epsilon_cutoff=float(cutoff), mcmc=str(args.mcmc.resolve()),
                    mcmc_reference=reference, streams=identities, plan=plan, config=config,
                    sources={name: digest(REPO / name) for name in SOURCES},
                    files={p.name: digest(p) for p in sorted(args.output.glob("*.npy"))})
    write_json(args.output / "inputs.json", settings)
    save_rows(args.output / "streams.csv", identities)
    (args.output / "completed").touch()
    print(f"Validated and cached {len(streams)} streams: {args.output}", flush=True)


def load_cache(path):
    if not (path / "completed").is_file():
        raise ValueError("Cache has no completion marker")
    settings = read_json(path / "inputs.json")
    if settings["schema"] != SCHEMA:
        raise ValueError("Unsupported cache schema")
    for name, expected in settings["sources"].items():
        if digest(REPO / name) != expected:
            raise ValueError(f"Analysis source changed after caching: {name}")
    for name, expected in settings["files"].items():
        if digest(path / name) != expected:
            raise ValueError(f"Cache hash mismatch: {name}")
    streams = []
    for i in range(settings["stream_count"]):
        data = np.load(path / f"stream_{i:02d}.npy", allow_pickle=False)
        obs = dict(zip(OBSERVABLES, data.T))
        obs["energy"] = 2 * obs["action_density"]
        obs["stream_index"] = np.full(len(data), i)
        streams.append(NestedSamplingStream(obs["energy"], obs, settings["n_live"]))
    return settings, streams, np.load(path / "edges.npy"), np.load(path / "blocks.npy")


def task_spec(settings, task):
    if not 0 <= task <= settings["orderings"]:
        raise ValueError("Array task outside planned range")
    n = settings["stream_count"]
    if task == 0:
        return [("old12", list(range(n // 2))), ("new12", list(range(n // 2, n))), ("full24", list(range(n)))]
    return [(f"k{k}", ids) for k, ids in settings["plan"][task - 1]["subsets"].items()]


def result_rows(label, selected, values, errors, draws, edges, blocks, settings):
    rows = []
    for key in STATISTICS:
        mc = settings["mcmc_reference"].get(key)
        delta = None if mc is None else values[key] - mc["estimate"]
        se = None if mc is None else float(np.hypot(errors[key], mc["se"]))
        rows.append(dict(subset=label, streams=len(selected), observable=key, estimate=values[key],
                         bootstrap_se=errors[key], mcmc_mean=None if mc is None else mc["estimate"],
                         mcmc_se=None if mc is None else mc["se"],
                         delta_mcmc=delta, delta_se=se,
                         delta_over_se=delta / se if se is not None and se > 0 else None))
    count = settings["bins"]
    total = blocks.sum(axis=0)
    bins, _ = comparison(unpack(values, count), total)
    ns_draws, _ = comparison(unpack(draws, count), total)
    mc_draws, _ = comparison(unpack(values, count), total - blocks)
    bin_rows = []
    for name in ("G0", "Gk"):
        ns_error = ns_draws[f"ns_{name}"].std(axis=0, ddof=1)
        mc_error = np.sqrt(len(blocks) - 1) * mc_draws[f"mcmc_{name}"].std(axis=0)
        for i in range(count):
            bin_rows.append(dict(subset=label, streams=len(selected), observable=name, bin=i + 1,
                                 epsilon_lo=float(edges[i]), epsilon_hi=float(edges[i + 1]),
                                 estimate=float(bins[f"ns_{name}"][i]), ns_se=float(ns_error[i]),
                                 mcmc_mean=float(bins[f"mcmc_{name}"][i]), mcmc_se=float(mc_error[i]),
                                 delta_mcmc=float(bins[f"delta_{name}"][i]),
                                 delta_se=float(np.hypot(ns_error[i], mc_error[i]))))
    return rows, bin_rows


def evaluate(args):
    settings, streams, edges, blocks = load_cache(args.cache)
    fingerprint = digest(args.cache / "inputs.json")
    spec = task_spec(settings, args.task)
    signature = dict(cache_sha256=fingerprint, task=args.task, subsets=spec)
    # Normalize tuples to lists for exact comparison after JSON serialization.
    signature = json.loads(json.dumps(signature))
    args.output.mkdir(parents=True, exist_ok=True)
    tag = args.output / "task.json"
    if tag.exists() and read_json(tag) != signature:
        raise ValueError("Existing task output belongs to a different cache or plan")
    write_json(tag, signature)
    stat = partial(statistic, edges={settings["bins"]: edges}, lattice=settings["lattice"], beta=settings["beta"])
    for slot, (label, selected) in enumerate(spec):
        destination = args.output / label
        if (destination / "result.json").exists():
            if read_json(destination / "result.json")["selected"] != selected:
                raise ValueError(f"Stored subset does not match plan: {label}")
            print(f"Reusing completed subset {label}", flush=True)
            continue
        work = Path(tempfile.mkdtemp(prefix=f".{label}.", dir=args.output))
        seed = int(np.random.SeedSequence([settings["seed"], 23, args.task, slot]).generate_state(1)[0])
        print(f"Task {args.task}: {label}, {len(selected)} streams, {settings['bootstrap']} bootstrap draws", flush=True)
        started = time.perf_counter()
        values, errors, draws = bootstrap_nested_sampling([streams[i] for i in selected], stat, settings["bootstrap"], seed)
        rows, bins = result_rows(label, selected, values, errors, draws, edges, blocks, settings)
        save_rows(work / "observables.csv", rows)
        save_rows(work / "bins.csv", bins)
        if args.task == 0:
            write_comparison(work / "comparison", edges, unpack(values, settings["bins"]),
                             unpack(draws, settings["bins"]), blocks, settings["joint_draws"], seed,
                             f"L={settings['lattice']}, β={settings['beta']:g}, {label}, block {settings['block_size']}")
        write_json(work / "result.json", dict(label=label, selected=selected, bootstrap_seed=seed,
                                             elapsed_seconds=time.perf_counter() - started,
                                             observables=rows, bins=bins))
        work.rename(destination)
    (args.output / "completed").touch()


def scaling_summary(rows, full_rows, value_key, error_key, component_keys):
    """Keep finite-population subset scatter separate from bootstrap errors."""
    result = []
    groups = {}
    reference = {tuple(row[k] for k in component_keys): row for row in full_rows}
    for row in rows:
        groups.setdefault((row["streams"], *(row[k] for k in component_keys)), []).append(row)
    for (count, *component), group in sorted(groups.items()):
        values = np.array([r[value_key] for r in group])
        errors = np.array([r[error_key] for r in group])
        full = reference[tuple(component)]
        result.append(dict(streams=count, **dict(zip(component_keys, component)), subsets=len(group),
                           estimate_median=float(np.median(values)), estimate_p10=float(np.quantile(values, .1)),
                           estimate_p90=float(np.quantile(values, .9)),
                           subset_estimate_sd=float(values.std(ddof=1)) if len(values) > 1 else 0.,
                           ns_se_median=float(np.median(errors)), ns_se_p10=float(np.quantile(errors, .1)),
                           ns_se_p90=float(np.quantile(errors, .9)), se_sqrt_k=float(np.median(errors) * np.sqrt(count)),
                           independent_scaling_reference=float(full[error_key] * np.sqrt(full["streams"] / count))))
    return result


def old_new_differences(old, new):
    rows = []
    for table, keys, error_key in (("observables", ("observable",), "bootstrap_se"),
                                   ("bins", ("observable", "bin"), "ns_se")):
        lookup = {tuple(r[k] for k in keys): r for r in new[table]}
        for a in old[table]:
            b = lookup[tuple(a[k] for k in keys)]
            delta, se = a["estimate"] - b["estimate"], float(np.hypot(a[error_key], b[error_key]))
            rows.append(dict(kind=table, observable=a["observable"], bin=a.get("bin"),
                             old_mean=a["estimate"], new_mean=b["estimate"], old_minus_new=delta,
                             independent_ns_se=se, difference_over_se=delta / se if se > 0 else None))
    return rows


def plot_scaling(path, summary, baseline, bins, settings):
    keys = ("mean_action_density", "xi_L_squared", "chi_topological", "mean_G0", "mean_Gk")
    fig, axes = plt.subplots(2, 3, figsize=(13, 7), constrained_layout=True)
    for ax, key in zip(axes.flat, keys):
        rows = [r for r in summary if r["observable"] == key]
        x = np.array([r["streams"] for r in rows])
        ax.plot(x, [r["ns_se_median"] for r in rows], "o-", label="Median stream-bootstrap SE")
        ax.fill_between(x, [r["ns_se_p10"] for r in rows], [r["ns_se_p90"] for r in rows], alpha=.2, label="Subset 10–90% range")
        ax.plot(x, [r["independent_scaling_reference"] for r in rows], "--", color="0.4", label=r"Full SE × $\sqrt{24/k}$")
        ax.set(title=key, xlabel="Streams k", ylabel="NS standard error")
    handles, labels = axes.flat[0].get_legend_handles_labels()
    axes.flat[-1].axis("off"); axes.flat[-1].legend(handles, labels, loc="center")
    fig.savefig(path / "error_scaling.png", dpi=160); plt.close(fig)
    fig, axes = plt.subplots(2, 3, figsize=(13, 7), constrained_layout=True)
    for ax, key in zip(axes.flat, keys):
        rows = [r for r in summary if r["observable"] == key]
        x = [r["streams"] for r in rows]
        ax.plot(x, [r["estimate_median"] for r in rows], "o-")
        ax.fill_between(x, [r["estimate_p10"] for r in rows], [r["estimate_p90"] for r in rows], alpha=.2)
        for name, color in (("old12", "C1"), ("new12", "C2")):
            r = next(r for r in baseline[name]["observables"] if r["observable"] == key)
            ax.errorbar([12], [r["estimate"]], yerr=[r["bootstrap_se"]], fmt="s", color=color, label=name)
        r = next(r for r in baseline["full24"]["observables"] if r["observable"] == key)
        ax.errorbar([24], [r["estimate"]], yerr=[r["bootstrap_se"]], fmt="ks", label="Full24 ± NS SE")
        mc = settings["mcmc_reference"][key]
        ax.axhline(mc["estimate"], color="0.3", linestyle="--", label="MCMC")
        ax.set(title=key, xlabel="Streams k", ylabel="Estimate (subset range shaded)")
    axes.flat[-1].axis("off")
    handles, labels = axes.flat[0].get_legend_handles_labels(); axes.flat[-1].legend(handles, labels, loc="center")
    fig.savefig(path / "estimate_scaling.png", dpi=160); plt.close(fig)
    fig, ax = plt.subplots(figsize=(8, 4.5), constrained_layout=True)
    selected = [r for r in bins if r["observable"] == "G0" and r["bin"] == settings["focus_bin"]]
    for ordering in sorted({r["ordering"] for r in selected if r["ordering"] >= 0}):
        rows = sorted((r for r in selected if r["ordering"] == ordering), key=lambda r:r["streams"])
        ax.plot([r["streams"] for r in rows], [r["delta_mcmc"] for r in rows], "o-", alpha=.35)
    full = next(r for r in baseline["full24"]["bins"] if r["observable"] == "G0" and r["bin"] == settings["focus_bin"])
    ax.errorbar([24], [full["delta_mcmc"]], yerr=[full["delta_se"]], fmt="ks", capsize=4, label="Full24 ± marginal SE")
    ax.axhline(0, color="0.4", linestyle="--")
    ax.set(xlabel="Streams k", ylabel="Conditional G0: NS − MCMC", title=f"Fixed action bin {settings['focus_bin']}; each line is one ordering")
    ax.legend(); fig.savefig(path / "focus_G0_scaling.png", dpi=160); plt.close(fig)


def collect(args):
    if args.output.exists():
        raise ValueError(f"Refusing to overwrite report: {args.output}")
    if not (args.cache / "completed").is_file():
        raise ValueError("Cache has no completion marker")
    settings = read_json(args.cache / "inputs.json")
    fingerprint = digest(args.cache / "inputs.json")
    baseline, rows, bins = {}, [], []
    for task in range(settings["orderings"] + 1):
        root = args.evaluations / f"task_{task}"
        expected = json.loads(json.dumps(dict(cache_sha256=fingerprint, task=task, subsets=task_spec(settings, task))))
        if not (root / "completed").is_file() or read_json(root / "task.json") != expected:
            raise ValueError(f"Missing, incomplete or mismatched task: {root}")
        for label, _ in task_spec(settings, task):
            result = read_json(root / label / "result.json")
            if result["selected"] != dict(task_spec(settings, task))[label]:
                raise ValueError(f"Stored subset does not match plan: {root / label}")
            if task == 0:
                baseline[label] = result
            else:
                rows.extend(dict(ordering=task - 1, **r) for r in result["observables"])
                bins.extend(dict(ordering=task - 1, **r) for r in result["bins"])
    # Full24 is one result, not another repeated random subset.
    rows.extend(dict(ordering=-1, **r) for r in baseline["full24"]["observables"])
    bins.extend(dict(ordering=-1, **r) for r in baseline["full24"]["bins"])
    summary = scaling_summary(rows, baseline["full24"]["observables"], "estimate", "bootstrap_se", ("observable",))
    conditional = scaling_summary(bins, baseline["full24"]["bins"], "delta_mcmc", "ns_se", ("observable", "bin"))
    args.output.mkdir(parents=True)
    save_rows(args.output / "subset_observables.csv", rows)
    save_rows(args.output / "subset_bins.csv", bins)
    save_rows(args.output / "scaling_summary.csv", summary)
    save_rows(args.output / "conditional_scaling.csv", conditional)
    save_rows(args.output / "old_new_differences.csv", old_new_differences(baseline["old12"], baseline["new12"]))
    save_rows(args.output / "baseline_observables.csv", [r for result in baseline.values() for r in result["observables"]])
    write_json(args.output / "inputs.json", dict(cache=str(args.cache.resolve()), cache_sha256=fingerprint,
                                               evaluations=str(args.evaluations.resolve()), settings=settings))
    plot_scaling(args.output, summary, baseline, bins, settings)
    (args.output / "completed").touch()
    print(f"Completed stream-count report: {args.output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    p = modes.add_parser("prepare")
    p.add_argument("--ns", nargs=6, required=True, type=Path)
    p.add_argument("--mcmc", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--expected-lattice", type=int, default=120)
    p.add_argument("--expected-stoc", type=int, default=86400)
    p.add_argument("--updates", type=int, default=300000)
    p.add_argument("--beta", type=float, default=1.)
    p.add_argument("--burn-in", type=int, default=20000)
    p.add_argument("--block-size", type=int, default=512)
    p.add_argument("--bins", type=int, default=32)
    p.add_argument("--focus-bin", type=int, default=9)
    p.add_argument("--tail", type=float, default=.005)
    p.add_argument("--counts", nargs="+", type=int, default=[6, 8, 12, 16, 20, 24])
    p.add_argument("--orderings", type=int, default=8)
    p.add_argument("--bootstrap", type=int, default=200)
    p.add_argument("--joint-draws", type=int, default=1000)
    p.add_argument("--seed", type=int, default=20261125)
    p = modes.add_parser("evaluate")
    p.add_argument("--cache", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--task", required=True, type=int)
    p = modes.add_parser("collect")
    p.add_argument("--cache", required=True, type=Path)
    p.add_argument("--evaluations", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.mode == "prepare" and (args.bootstrap < 2 or args.joint_draws < 2 or args.seed < 0 or args.updates < 1
            or args.bins < 2 or not 1 <= args.focus_bin <= args.bins or not 0 < args.tail < .5
            or not np.isfinite(args.beta) or args.beta < .7 or args.burn_in < 0
            or args.block_size < 1 or args.block_size & (args.block_size - 1)):
        parser.error("Invalid draws, seed, bin, block, beta, depth or burn-in settings")
    try:
        {"prepare": prepare, "evaluate": evaluate, "collect": collect}[args.mode](args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
