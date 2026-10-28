"""Utilities for combining and bootstrapping nested-sampling streams.

The bootstrap unit is a complete, independently seeded stream. A replicate
draws streams with replacement, merges their dead points by decreasing energy,
and recomputes the nested-sampling weights using the corresponding total number
of live points. This preserves within-stream correlations.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.special import logsumexp

Array = np.ndarray


def read_summary(path: str | Path) -> dict[str, Array]:
    """Read ``name: mean +/- error`` entries from a text file.

    Each dictionary value is a two-element NumPy array containing the mean
    and error, respectively.
    """

    result: dict[str, Array] = {}
    with Path(path).open(encoding="utf-8") as summary_file:
        for line_number, raw_line in enumerate(summary_file, start=1):
            line = raw_line.strip()
            if not line:
                continue

            name, colon, values = line.partition(":")
            mean, separator, error = values.partition("+/-")
            name = name.strip()
            if not colon or not separator or not name:
                raise ValueError(
                    f"invalid summary entry on line {line_number}: {line!r}"
                )
            if name in result:
                raise ValueError(f"duplicate summary key {name!r} on line {line_number}")

            try:
                result[name] = np.array([float(mean), float(error)], dtype=float)
            except ValueError as exc:
                raise ValueError(
                    f"invalid numeric value on line {line_number}: {line!r}"
                ) from exc

    return result


@dataclass(frozen=True)
class NestedSamplingStream:
    """Measurements from one independent nested-sampling run."""

    energy: Array
    observables: Mapping[str, Array]
    n_live: int
    name: str = ""

    def __post_init__(self) -> None:
        energy = np.asarray(self.energy, dtype=float)
        if energy.ndim != 1 or energy.size == 0:
            raise ValueError("energy must be a non-empty one-dimensional array")
        if self.n_live <= 0:
            raise ValueError("n_live must be positive")
        for name, values in self.observables.items():
            if np.asarray(values).shape != energy.shape:
                raise ValueError(f"observable {name!r} does not match energy")


@dataclass(frozen=True)
class CombinedNestedSampling:
    """Energy-ordered data and deterministic nested-sampling quadrature."""

    energy: Array
    observables: dict[str, Array]
    log_x: Array
    log_weight: Array
    log_weight_normalized: Array
    log_z: float
    log_z_curve: Array
    n_live_effective: int

    @property
    def weight(self) -> Array:
        return np.exp(self.log_weight_normalized)

    def weighted_sum(self, values: Array) -> float:
        """Return ``sum(weight * values)`` while recovering underflowed terms.

        Direct products retain the best precision when signed observations
        nearly cancel.  Terms whose products underflow to zero are accumulated
        separately with signed log-sum-exp and then added back.
        """

        values = np.asarray(values, dtype=float)
        if values.shape != self.log_weight_normalized.shape:
            raise ValueError("values do not match the nested-sampling weights")
        if not np.all(np.isfinite(values)):
            raise ValueError("values must be finite")

        with np.errstate(under="ignore"):
            products = self.weight * values
        total = float(np.sum(products))

        underflowed = (products == 0.0) & (values != 0.0)
        if np.any(underflowed):
            log_absolute_tail, tail_sign = logsumexp(
                self.log_weight_normalized[underflowed],
                b=values[underflowed],
                return_sign=True,
            )
            if tail_sign != 0.0:
                total += float(tail_sign * np.exp(log_absolute_tail))
        return total

    def mean(self, name: str) -> float:
        return self.weighted_sum(self.observables[name])

    def log_mean(self, name: str) -> float:
        """Return the log mean of a non-negative observable.

        Keeping the result in log space also represents means too small to
        return as ordinary floating-point numbers.  Zero-valued measurements
        are handled naturally; an all-zero observable has log mean ``-inf``.
        """

        values = np.asarray(self.observables[name], dtype=float)
        if np.any(values < 0.0):
            raise ValueError("log_mean requires a non-negative observable")
        if not np.all(np.isfinite(values)):
            raise ValueError("observable values must be finite")
        return float(logsumexp(self.log_weight_normalized, b=values))

    def variance(self, name: str, mean: float | None = None) -> float:
        """Return a centered weighted variance for an observable."""

        values = np.asarray(self.observables[name], dtype=float)
        if mean is None:
            mean = self.weighted_sum(values)
        return self.weighted_sum((values - mean) ** 2)


def combine_streams(streams: Sequence[NestedSamplingStream]) -> CombinedNestedSampling:
    """Merge streams by energy and calculate expected-shrinkage weights.

    The convention matches ``checking_ns_heatbath_local_ubelix.ipynb``:
    dead points are ordered from largest to smallest energy and the expected
    shrinkage is ``exp(-1 / sum(n_live))``.
    """

    if not streams:
        raise ValueError("at least one stream is required")
    keys = set(streams[0].observables)
    if any(set(stream.observables) != keys for stream in streams[1:]):
        raise ValueError("all streams must contain the same observables")

    energy = np.concatenate([np.asarray(s.energy, dtype=float) for s in streams])
    order = np.argsort(energy, kind="stable")[::-1]
    energy = energy[order]
    observables = {
        key: np.concatenate([np.asarray(s.observables[key], dtype=float) for s in streams])[order]
        for key in sorted(keys)
    }
    n_live_effective = sum(s.n_live for s in streams)
    log_t = -1.0 / n_live_effective
    log_delta_x = np.log(-np.expm1(log_t))
    log_weight = np.arange(energy.size, dtype=float) * log_t + log_delta_x
    log_x = (np.arange(energy.size, dtype=float) + 1.0) * log_t
    log_z = float(logsumexp(log_weight))
    return CombinedNestedSampling(
        energy=energy,
        observables=observables,
        log_x=log_x,
        log_weight=log_weight,
        log_weight_normalized=log_weight - log_z,
        log_z=log_z,
        log_z_curve=np.logaddexp.accumulate(log_weight) - log_z,
        n_live_effective=n_live_effective,
    )


def reweight_beta(
    data: CombinedNestedSampling,
    source_beta: float,
    target_beta: float,
    cpn_n: int,
    volume: int,
) -> tuple[CombinedNestedSampling, float, float]:
    """Reweight canonical quadrature weights from ``source_beta`` to ``target_beta``.

    The measured action density is
    ``epsilon = S_beta / (2 * beta * N * V)``, so the beta-independent
    extensive energy is ``H = 2 * N * V * epsilon``.  Reweighting therefore
    adds ``-(target_beta - source_beta) * H`` to every log weight.  All other
    action parameters, including theta, are held fixed by construction.

    Returns ``(reweighted_data, log_Z_ratio, quadrature_ess)``.  The effective
    sample size describes concentration of deterministic quadrature weights;
    it is not a count of independent Markov-chain samples.
    """

    if cpn_n <= 0:
        raise ValueError("cpn_n must be positive")
    if volume <= 0:
        raise ValueError("volume must be positive")
    if not np.isfinite(source_beta) or not np.isfinite(target_beta):
        raise ValueError("source_beta and target_beta must be finite")
    if "action_density" not in data.observables:
        raise ValueError("beta reweighting requires the action_density observable")

    action_density = np.asarray(data.observables["action_density"], dtype=float)
    if action_density.shape != data.log_weight.shape:
        raise ValueError("action_density does not match the nested-sampling weights")
    if not np.all(np.isfinite(action_density)):
        raise ValueError("action_density must be finite")

    extensive_energy = 2.0 * cpn_n * volume * action_density
    with np.errstate(over="ignore", invalid="ignore"):
        log_beta_factor = -(target_beta - source_beta) * extensive_energy
    if not np.all(np.isfinite(log_beta_factor)):
        raise ValueError("non-finite beta-reweighting exponent")

    log_weight = data.log_weight + log_beta_factor
    log_z_ratio = float(logsumexp(log_weight))
    log_weight_normalized = log_weight - log_z_ratio
    log_quadrature_ess = -float(logsumexp(2.0 * log_weight_normalized))
    quadrature_ess = float(np.exp(log_quadrature_ess))
    reweighted = CombinedNestedSampling(
        energy=data.energy,
        observables=data.observables,
        log_x=data.log_x,
        log_weight=log_weight,
        log_weight_normalized=log_weight_normalized,
        log_z=log_z_ratio,
        log_z_curve=np.logaddexp.accumulate(log_weight) - log_z_ratio,
        n_live_effective=data.n_live_effective,
    )
    return reweighted, log_z_ratio, quadrature_ess


def bootstrap_nested_sampling(
    streams: Sequence[NestedSamplingStream],
    statistic: Callable[[CombinedNestedSampling], Mapping[str, float]],
    n_bootstrap: int = 1000,
    seed: int | None = None,
) -> tuple[dict[str, float], dict[str, float], dict[str, Array]]:
    """Estimate statistics and stream-bootstrap standard errors.

    Returns ``(estimate, error, samples)``. Errors are sample standard
    deviations (``ddof=1``) across replicates.
    """

    if len(streams) < 2:
        raise ValueError("stream bootstrap requires at least two independent runs")
    if n_bootstrap < 2:
        raise ValueError("n_bootstrap must be at least 2")
    estimate = {key: float(value) for key, value in statistic(combine_streams(streams)).items()}
    samples = {key: np.empty(n_bootstrap, dtype=float) for key in estimate}
    rng = np.random.default_rng(seed)
    for sample_index in range(n_bootstrap):
        selected = [streams[i] for i in rng.integers(0, len(streams), size=len(streams))]
        values = statistic(combine_streams(selected))
        if set(values) != set(estimate):
            raise ValueError("statistic returned inconsistent keys")
        for key, value in values.items():
            samples[key][sample_index] = float(value)
    errors = {key: float(np.std(values, ddof=1)) for key, values in samples.items()}
    return estimate, errors, samples

