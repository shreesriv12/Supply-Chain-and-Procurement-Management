from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import joblib
import pandas as pd

from .common import FORECAST_MODEL, LATE_MODEL


@lru_cache(maxsize=4)
def _load_cached(
    path: str,
    modified_ns: int,
    size: int,
) -> dict[str, Any]:
    """Load a model once, reusing it until the model file changes."""
    return joblib.load(path)


def _load_artifact(
    path: Path,
    missing_message: str,
) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(missing_message)

    stat = path.stat()

    return _load_cached(
        str(path),
        stat.st_mtime_ns,
        stat.st_size,
    )


def late_probability(row: dict) -> tuple[float, str]:
    artifact = _load_artifact(
        LATE_MODEL,
        "Late-delivery model is not trained. "
        "Run python -m app.ml.train_late",
    )

    features = artifact["features"]
    frame = pd.DataFrame([row])[features]

    probability = float(
        artifact["pipeline"].predict_proba(frame)[0, 1]
    )

    return probability, artifact["model_name"]


def forecast_demand(row: dict) -> float:
    artifact = _load_artifact(
        FORECAST_MODEL,
        "Demand forecast model is not trained. "
        "Run python -m app.ml.train_forecast",
    )

    features = artifact["features"]
    frame = pd.DataFrame([row])[features]

    prediction = float(
        artifact["model"].predict(frame)[0]
    )

    return max(0.0, prediction)