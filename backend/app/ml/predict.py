from __future__ import annotations
import joblib
import pandas as pd
from .common import FORECAST_MODEL, LATE_MODEL

def late_probability(row: dict) -> tuple[float, str]:
    if not LATE_MODEL.exists(): raise FileNotFoundError("Late-delivery model is not trained. Run python -m app.ml.train_late")
    artifact = joblib.load(LATE_MODEL); probability = float(artifact["pipeline"].predict_proba(pd.DataFrame([row])[artifact["features"]])[:,1][0])
    return probability, artifact["model_name"]

def forecast_demand(row: dict) -> float:
    if not FORECAST_MODEL.exists(): raise FileNotFoundError("Demand forecast model is not trained. Run python -m app.ml.train_forecast")
    artifact = joblib.load(FORECAST_MODEL); return max(0.0, float(artifact["model"].predict(pd.DataFrame([row])[artifact["features"]])[0]))
