"""Read regular CPN Monte Carlo runs and estimate errors by binning."""

from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np

from .cpn_io import discover_runs, read_config


OBSERVABLES = ("mean_action_density", "mean_Q_U", "mean_Q_U_squared",
               "chi_topological", "xi_L_squared")


@dataclass(frozen=True)
class MCMCChain:
    path: Path
    size: tuple[int, int]
    beta: float
    theta: float
    seed: int
    meas_every: int
    cooling_step: int
    steps: np.ndarray
    action_density: np.ndarray
    g0: np.ndarray
    gk: np.ndarray
    q_u: np.ndarray

    def after_burn_in(self, burn_in: int) -> "MCMCChain":
        """Discard measurements whose stored MC step is at most burn_in."""
        if burn_in < 0:
            raise ValueError("burn-in must be nonnegative")
        start = np.searchsorted(self.steps, burn_in, side="right")
        if start == len(self.steps):
            raise ValueError(f"no measurements after burn-in in {self.path}")
        return replace(self, steps=self.steps[start:], action_density=self.action_density[start:],
                       g0=self.g0[start:], gk=self.gk[start:], q_u=self.q_u[start:])


def load_chain(path: Path, cooling_step: int | None = None) -> MCMCChain:
    config = read_config(path / "input.conf")
    if "num_ns_meas" in config:
        raise ValueError(f"expected regular MCMC input in {path}")
    try:
        lx, lt = map(int, config["size"])
        beta = float(config["beta"][0])
        theta = float(config["theta"][0])
        seed = int(config["rng_seed"][0])
        meas_every = int(config["meas_every"][0])
        max_cool = int(config["num_cool_step"][0])
        cool_every = int(config["meas_cool_every"][0])
        data_path = path / config["data_file"][0]
        topo_path = path / config["topo_file"][0]
    except (KeyError, ValueError, IndexError) as exc:
        raise ValueError(f"invalid MCMC input.conf in {path}: {exc}") from exc
    if min(lx, lt) <= 1 or meas_every < 1 or max_cool < 0 or cool_every < 1:
        raise ValueError(f"invalid size or measurement cadence in {path}")
    if not np.isfinite([beta, theta]).all():
        raise ValueError(f"invalid beta or theta in {path}")
    cooling = max_cool // cool_every * cool_every if cooling_step is None else cooling_step
    if cooling < 0 or cooling > max_cool or cooling % cool_every:
        raise ValueError(f"cooling step {cooling} is unavailable in {path}")

    data = np.loadtxt(data_path, ndmin=2)
    topo = np.loadtxt(topo_path, usecols=(0, 1, 2), ndmin=2)
    if not len(data) or data.shape[1] != 4 or not np.isfinite(data).all():
        raise ValueError(f"expected four finite measurement columns in {data_path}")
    steps = data[:, 0].astype(np.int64)
    if (not np.array_equal(steps, data[:, 0]) or np.any(steps < 0)
            or np.any(steps % meas_every) or np.any(np.diff(steps) != meas_every)):
        raise ValueError(f"measurement steps are out of order or irregular in {data_path}")
    selected = topo[topo[:, 1] == cooling]
    if not np.array_equal(steps, selected[:, 0]) or not np.isfinite(selected[:, 2]).all():
        raise ValueError(f"topology at cooling step {cooling} does not match {data_path}")
    return MCMCChain(path, (lx, lt), beta, theta, seed, meas_every, cooling,
                     steps, data[:, 1], data[:, 2], data[:, 3], selected[:, 2])


def _ensemble_settings(chain: MCMCChain) -> tuple:
    return chain.size, chain.beta, chain.theta, chain.meas_every, chain.cooling_step


def validate_ensemble(chains: list[MCMCChain]) -> None:
    if not chains:
        raise ValueError("at least one chain is required")
    if any(_ensemble_settings(chain) != _ensemble_settings(chains[0]) for chain in chains):
        raise ValueError("chains must share size, beta, theta, measurement cadence and cooling step")
    seeds = {chain.seed for chain in chains}
    if len(seeds) != len(chains) or min(seeds) <= 0:
        raise ValueError("use one chain per distinct positive RNG seed")


def load_ensemble(root: Path, cooling_step: int | None = None) -> list[MCMCChain]:
    root = root.expanduser().resolve()
    paths = [root] if (root / "input.conf").is_file() else discover_runs([root])
    chains = [load_chain(path, cooling_step) for path in paths]
    validate_ensemble(chains)
    return chains


def block_means(values: np.ndarray, block_size: int) -> np.ndarray:
    """Average contiguous equal-length blocks, discarding an incomplete tail."""
    if block_size < 1:
        raise ValueError("block size must be positive")
    values = np.asarray(values, dtype=float)
    n_blocks = len(values) // block_size
    shape = (n_blocks, block_size, *values.shape[1:])
    return values[:n_blocks * block_size].reshape(shape).mean(axis=1)


def _observables(means: np.ndarray, size: tuple[int, int], q_origin: float) -> np.ndarray:
    action, q_centered, q_centered_sq, g0, gk = means.T
    q = q_centered + q_origin
    q_sq = q_centered_sq + 2 * q_origin * q_centered + q_origin**2
    chi_top = (q_centered_sq - q_centered**2) / np.prod(size)
    ratio = np.divide(g0, gk, out=np.full_like(g0, np.nan), where=gk != 0)
    xi_sq = (ratio - 1) / (4 * np.sin(np.pi / min(size))**2)
    return np.column_stack((action, q, q_sq, chi_top, xi_sq))


@dataclass(frozen=True)
class BinningResult:
    block_size: int
    n_blocks: int
    estimate: np.ndarray
    standard_error: np.ndarray


def binning_analysis(chains: list[MCMCChain], min_blocks: int = 16) -> list[BinningResult]:
    """Scan powers of two with at least min_blocks complete bins in each chain.

    The pooled estimate weights measurements equally. Bins never cross
    chain boundaries. Delete-one-bin jackknife errors are meaningful once
    the bins are long compared to the relevant autocorrelations.
    """
    validate_ensemble(chains)
    if min_blocks < 2:
        raise ValueError("min_blocks must be at least two")
    max_size = min(len(chain.steps) for chain in chains) // min_blocks
    if not max_size:
        raise ValueError(f"each chain needs at least {min_blocks} retained measurements")
    q_origin = sum(np.sum(chain.q_u) for chain in chains) / sum(len(c.steps) for c in chains)
    values = []
    for chain in chains:
        q_centered = chain.q_u - q_origin
        values.append(np.column_stack((chain.action_density, q_centered, q_centered**2,
                                       chain.g0, chain.gk)))

    results = []
    for exponent in range(max_size.bit_length()):
        block_size = 2**exponent
        blocks = np.concatenate([block_means(x, block_size) for x in values])
        count = len(blocks)
        totals = blocks.sum(axis=0)
        estimate = _observables((totals / count)[None, :], chains[0].size, q_origin)[0]
        replicates = _observables((totals - blocks) / (count - 1), chains[0].size, q_origin)
        error = np.sqrt(count - 1) * np.std(replicates, axis=0)
        results.append(BinningResult(block_size, count, estimate, error))
    return results
