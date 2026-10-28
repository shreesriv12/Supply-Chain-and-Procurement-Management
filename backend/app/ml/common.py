from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import joblib
import pandas as pd
from dotenv import load_dotenv
from psycopg import connect
from psycopg.rows import dict_row

# On the host this resolves to the repository root; Docker supplies DATABASE_URL
# through Compose, so absence of a root .env inside the container is harmless.
PROJECT_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(PROJECT_ROOT / ".env")

MODEL_DIR = Path(os.getenv("MODEL_DIR", Path(__file__).parent / "models"))
LATE_MODEL = MODEL_DIR / "late_delivery.joblib"
FORECAST_MODEL = MODEL_DIR / "demand_forecast.joblib"


def read_frame(query: str, params: list[Any] | None = None) -> pd.DataFrame:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError(
            "DATABASE_URL is required for model training. Configure it in the project-root .env "
            "or run training inside the Compose API container."
        )
    with connect(database_url, row_factory=dict_row) as conn:
        return pd.DataFrame(conn.execute(query, params or []).fetchall())


def save_metrics(name: str, payload: dict[str, Any]) -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    (MODEL_DIR / f"{name}_metrics.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )