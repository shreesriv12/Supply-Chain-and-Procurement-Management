"""Train a monthly per-product demand forecaster against a naive lag-1 baseline."""
from __future__ import annotations
import argparse
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_absolute_percentage_error
from .common import FORECAST_MODEL, MODEL_DIR, read_frame, save_metrics

QUERY = """
SELECT product_id, date_trunc('month', moved_at)::date AS month, SUM(qty) AS demand
FROM stock_movement WHERE movement_type='OUT' GROUP BY product_id, date_trunc('month', moved_at)::date ORDER BY product_id, month
"""
FEATURES = ["product_id", "month_number", "lag_1", "lag_2", "lag_3", "rolling_3"]
def make_features(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy(); frame["month"] = pd.to_datetime(frame["month"]); frame = frame.sort_values(["product_id", "month"])
    complete = []
    for product_id, group in frame.groupby("product_id"):
        idx = pd.date_range(group.month.min(), group.month.max(), freq="MS")
        complete.append(group.set_index("month").reindex(idx, fill_value=0).assign(product_id=product_id).rename_axis("month").reset_index())
    frame = pd.concat(complete, ignore_index=True); frame["month_number"] = frame.month.dt.month
    group = frame.groupby("product_id")["demand"]
    for lag in (1,2,3): frame[f"lag_{lag}"] = group.shift(lag)
    frame["rolling_3"] = group.transform(lambda values: values.shift(1).rolling(3).mean())
    return frame.dropna().reset_index(drop=True)
def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--test-fraction", type=float, default=.2); args = parser.parse_args()
    frame = make_features(read_frame(QUERY))
    if len(frame) < 50: raise RuntimeError("Need at least 50 monthly product observations to train")
    cutoff = frame.month.quantile(1-args.test_fraction); train, test = frame[frame.month <= cutoff], frame[frame.month > cutoff]
    model = HistGradientBoostingRegressor(max_iter=200, learning_rate=.08, max_leaf_nodes=20, random_state=42).fit(train[FEATURES], train.demand)
    predicted, baseline = np.maximum(0, model.predict(test[FEATURES])), test.lag_1
    metrics = {"train_rows": len(train), "test_rows": len(test), "mae": float(mean_absolute_error(test.demand, predicted)), "mape": float(mean_absolute_percentage_error(test.demand, np.maximum(1, predicted))), "naive_mae": float(mean_absolute_error(test.demand, baseline)), "naive_mape": float(mean_absolute_percentage_error(test.demand, np.maximum(1, baseline)))}
    MODEL_DIR.mkdir(parents=True, exist_ok=True); joblib.dump({"model": model, "features": FEATURES}, FORECAST_MODEL); save_metrics("demand_forecast", metrics); print(f"Saved {FORECAST_MODEL}; MAE={metrics['mae']:.2f}")
if __name__ == "__main__": main()
