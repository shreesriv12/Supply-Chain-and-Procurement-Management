"""Train project ML models on local public datasets without loading them into core transactions.

DataCo supplies real delivery outcomes; M5 supplies retail demand series. Synthetic
PostgreSQL data remains the source for live app predictions and database demos.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import accuracy_score, f1_score, mean_absolute_error, mean_absolute_percentage_error, precision_score, recall_score, roc_auc_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from .common import MODEL_DIR, save_metrics

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "datasets"

def train_dataco(path: Path, max_rows: int) -> dict:
    use = ["Late_delivery_risk", "order date (DateOrders)", "Days for shipment (scheduled)", "Sales per customer", "Order Item Quantity", "Order Item Product Price", "Category Name", "Market", "Shipping Mode", "Order Region"]
    frame = pd.read_csv(path, usecols=use, encoding="latin-1", low_memory=False, nrows=max_rows).dropna(subset=["Late_delivery_risk", "order date (DateOrders)"])
    frame["order_date"] = pd.to_datetime(frame.pop("order date (DateOrders)"), errors="coerce"); frame = frame.dropna(subset=["order_date"]).sort_values("order_date")
    target = frame.pop("Late_delivery_risk").astype(int); frame["order_month"] = frame.order_date.dt.month; frame = frame.drop(columns="order_date")
    categorical = [name for name in frame if frame[name].dtype == "object"]; numeric = [name for name in frame if name not in categorical]
    cut = int(len(frame) * .8); X_train, X_test, y_train, y_test = frame.iloc[:cut], frame.iloc[cut:], target.iloc[:cut], target.iloc[cut:]
    prep = ColumnTransformer([("numeric", SimpleImputer(strategy="median"), numeric), ("category", Pipeline([("impute", SimpleImputer(strategy="most_frequent")), ("onehot", OneHotEncoder(handle_unknown="ignore"))]), categorical)])
    model = Pipeline([("prep", prep), ("model", RandomForestClassifier(n_estimators=120, min_samples_leaf=4, class_weight="balanced", n_jobs=-1, random_state=42))])
    model.fit(X_train, y_train); probability = model.predict_proba(X_test)[:,1]; predicted = (probability >= .5).astype(int)
    artifact = MODEL_DIR / "dataco_late_delivery.joblib"; MODEL_DIR.mkdir(parents=True, exist_ok=True); joblib.dump({"pipeline": model, "features": list(frame.columns), "source": "DataCo Supply Chain"}, artifact)
    metrics = {"source": "DataCo Supply Chain", "rows": len(frame), "train_rows": len(X_train), "test_rows": len(X_test), "roc_auc": float(roc_auc_score(y_test, probability)), "accuracy": float(accuracy_score(y_test, predicted)), "precision": float(precision_score(y_test, predicted, zero_division=0)), "recall": float(recall_score(y_test, predicted, zero_division=0)), "f1": float(f1_score(y_test, predicted, zero_division=0)), "model_file": str(artifact)}
    save_metrics("dataco_late_delivery", metrics); return metrics

def train_m5(path: Path, max_series: int) -> dict:
    wide = pd.read_csv(path, nrows=max_series)
    day_cols = [name for name in wide.columns if name.startswith("d_")]; values = wide[day_cols].to_numpy(dtype="float32")
    records = []
    for series_index, sales in enumerate(values):
        for t in range(28, len(sales)):
            records.append((series_index, (t % 365) // 30 + 1, sales[t-1], sales[t-7], sales[t-28], sales[t-28:t].mean(), sales[t]))
    frame = pd.DataFrame(records, columns=["series", "month", "lag_1", "lag_7", "lag_28", "rolling_28", "demand"])
    cut = int(len(frame) * .8); train, test = frame.iloc[:cut], frame.iloc[cut:]
    features = ["series", "month", "lag_1", "lag_7", "lag_28", "rolling_28"]
    model = HistGradientBoostingRegressor(max_iter=200, learning_rate=.08, max_leaf_nodes=24, random_state=42).fit(train[features], train.demand)
    predicted = model.predict(test[features]); baseline = test.lag_1
    artifact = MODEL_DIR / "m5_demand_forecast.joblib"; MODEL_DIR.mkdir(parents=True, exist_ok=True); joblib.dump({"model": model, "features": features, "source": "M5 Forecasting Accuracy"}, artifact)
    positive = test.demand > 0
    metrics = {"source": "M5 Forecasting Accuracy", "series_used": max_series, "train_rows": len(train), "test_rows": len(test), "mae": float(mean_absolute_error(test.demand, predicted)), "mape_nonzero_demand": float(mean_absolute_percentage_error(test.loc[positive, "demand"], predicted[positive])), "naive_mae": float(mean_absolute_error(test.demand, baseline)), "naive_mape_nonzero_demand": float(mean_absolute_percentage_error(test.loc[positive, "demand"], baseline.loc[positive])), "model_file": str(artifact)}
    save_metrics("m5_demand_forecast", metrics); return metrics

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--dataset", choices=["dataco", "m5", "all"], default="all"); parser.add_argument("--m5-series", type=int, default=300); parser.add_argument("--dataco-rows", type=int, default=60000); args = parser.parse_args()
    outcomes = {}
    if args.dataset in ("dataco", "all"): outcomes["dataco"] = train_dataco(DATA / "DataCoSupplyChainDataset.csv", args.dataco_rows)
    if args.dataset in ("m5", "all"): outcomes["m5"] = train_m5(DATA / "sales_train_validation.csv", args.m5_series)
    for name, metrics in outcomes.items(): print(f"{name}: {metrics}")
if __name__ == "__main__": main()
