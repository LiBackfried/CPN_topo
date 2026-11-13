"""Common input-file and run-directory helpers for CP(N-1) analysis."""

from __future__ import annotations

import re
from pathlib import Path


def read_config(path: Path) -> dict[str, list[str]]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("#", 1)[0].split()
        if fields:
            result[fields[0]] = fields[1:]
    return result


def discover_runs(roots: list[Path]) -> list[Path]:
    runs = []
    for root in roots:
        root = root.expanduser().resolve()
        if (root / "dati.dat").is_file():
            found = [root]
        else:
            found = [p for p in root.iterdir()
                     if p.is_dir() and re.fullmatch(r"run_?\d+", p.name)]
            found.sort(key=lambda p: int(re.search(r"\d+$", p.name).group()))
        if not found:
            raise FileNotFoundError(f"no run directories found under {root}")
        runs.extend(found)
    return list(dict.fromkeys(runs))
