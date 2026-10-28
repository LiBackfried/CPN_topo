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

    def mean(self, name: str) -> float:
        return float(np.sum(self.weight * self.observables[name]))


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
    log_weight = np.arange(energy.size, dtype=float) * log_t + np.log1p(-np.exp(log_t))
    log_x = (np.arange(energy.size, dtype=float) + 1.0) * log_t
    log_z = float(np.logaddexp.reduce(log_weight))
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

