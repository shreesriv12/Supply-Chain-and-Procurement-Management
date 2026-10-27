"""Train late-delivery classifier using an order-date time split (no future leakage)."""
from __future__ import annotations
import argparse
from pathlib import Path
import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_score, recall_score, roc_auc_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from .common import LATE_MODEL, MODEL_DIR, read_frame, save_metrics

QUERY = """
WITH historical_supplier AS (
 SELECT po.po_id, AVG(CASE WHEN old.delivered_date <= old.expected_date THEN 1.0 ELSE 0.0 END) AS prior_on_time_rate
 FROM purchase_order po LEFT JOIN purchase_order old ON old.supplier_id=po.supplier_id AND old.order_date < po.order_date AND old.delivered_date IS NOT NULL
 GROUP BY po.po_id
), po_features AS (
 SELECT po.po_id, po.order_date, (po.delivered_date > po.expected_date)::int AS late,
 s.rating AS supplier_rating, hs.prior_on_time_rate, po.expected_date-po.order_date AS planned_lead_time,
 po.total_amount, COUNT(pi.line_no) AS line_count, SUM(pi.qty_ordered) AS total_qty,
 EXTRACT(MONTH FROM po.order_date)::int AS order_month, c.name AS category, w.city AS warehouse_city
 FROM purchase_order po JOIN supplier s USING(supplier_id) JOIN warehouse w USING(warehouse_id)
 JOIN po_item pi USING(po_id) JOIN product p USING(product_id) JOIN category c USING(category_id)
 LEFT JOIN historical_supplier hs USING(po_id)
 WHERE po.delivered_date IS NOT NULL GROUP BY po.po_id,s.rating,hs.prior_on_time_rate,c.name,w.city
)
SELECT * FROM po_features ORDER BY order_date
"""
NUMERIC = ["supplier_rating", "prior_on_time_rate", "planned_lead_time", "total_amount", "line_count", "total_qty", "order_month"]
CATEGORICAL = ["category", "warehouse_city"]

def build_pipeline(model):
    prep = ColumnTransformer([
      ("num", Pipeline([("impute", SimpleImputer(strategy="median")), ("scale", StandardScaler())]), NUMERIC),
      ("cat", Pipeline([("impute", SimpleImputer(strategy="most_frequent")), ("onehot", OneHotEncoder(handle_unknown="ignore"))]), CATEGORICAL),
    ])
    return Pipeline([("prep", prep), ("model", model)])

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--test-fraction", type=float, default=.2); args = parser.parse_args()
    frame = read_frame(QUERY)
    if len(frame) < 50 or frame.late.nunique() < 2: raise RuntimeError("Need at least 50 delivered POs and both delivery classes to train")
    cut = int(len(frame) * (1 - args.test_fraction)); train, test = frame.iloc[:cut], frame.iloc[cut:]
    X_train, y_train, X_test, y_test = train[NUMERIC+CATEGORICAL], train.late, test[NUMERIC+CATEGORICAL], test.late
    candidates = {"logistic_regression": build_pipeline(LogisticRegression(max_iter=1000, class_weight="balanced")), "random_forest": build_pipeline(RandomForestClassifier(n_estimators=300, min_samples_leaf=3, class_weight="balanced", random_state=42, n_jobs=-1))}
    scored = {}
    for name, pipeline in candidates.items():
        pipeline.fit(X_train, y_train); probability = pipeline.predict_proba(X_test)[:, 1]; predicted = (probability >= .5).astype(int)
        scored[name] = {"pipeline": pipeline, "roc_auc": float(roc_auc_score(y_test, probability)), "accuracy": float(accuracy_score(y_test, predicted)), "precision": float(precision_score(y_test, predicted, zero_division=0)), "recall": float(recall_score(y_test, predicted, zero_division=0)), "f1": float(f1_score(y_test, predicted, zero_division=0)), "confusion_matrix": confusion_matrix(y_test, predicted).tolist()}
    selected_name = max(scored, key=lambda name: scored[name]["roc_auc"]); selected = scored[selected_name]
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": selected.pop("pipeline"), "features": NUMERIC+CATEGORICAL, "model_name": selected_name}, LATE_MODEL)
    metrics = {"selected_model": selected_name, "train_rows": len(train), "test_rows": len(test), "candidates": {name: {key: value for key,value in values.items() if key != "pipeline"} for name,values in scored.items()}}
    save_metrics("late_delivery", metrics); print(f"Saved {LATE_MODEL}; selected {selected_name}, ROC-AUC={selected['roc_auc']:.3f}")
if __name__ == "__main__": main()
