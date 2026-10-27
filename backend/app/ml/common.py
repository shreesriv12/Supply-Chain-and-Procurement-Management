from __future__ import annotations
import json
import os
from pathlib import Path
from typing import Any
import joblib
import pandas as pd
from psycopg import connect
from psycopg.rows import dict_row

MODEL_DIR = Path(os.getenv("MODEL_DIR", Path(__file__).parent / "models"))
LATE_MODEL = MODEL_DIR / "late_delivery.joblib"
FORECAST_MODEL = MODEL_DIR / "demand_forecast.joblib"

def read_frame(query: str, params: list[Any] | None = None) -> pd.DataFrame:
    database_url = os.getenv("DATABASE_URL", "postgresql://scm_admin:scm_admin@localhost:5432/scm")
    with connect(database_url, row_factory=dict_row) as conn:
        return pd.DataFrame(conn.execute(query, params or []).fetchall())

def save_metrics(name: str, payload: dict[str, Any]) -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    (MODEL_DIR / f"{name}_metrics.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
