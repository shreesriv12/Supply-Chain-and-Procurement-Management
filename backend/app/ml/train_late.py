"""Train a late-delivery classifier without using information unavailable at order time."""
from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from .common import LATE_MODEL, MODEL_DIR, read_frame, save_metrics

# One observation per PO. The category feature uses the same deterministic
# representative category (MIN(category.name)) as the online prediction query.
# Historical supplier features include only orders delivered before this PO's
# order date; current/past-incomplete orders do not get mislabeled as late.
QUERY = """
SELECT
    po.po_id,
    po.order_date,
    (po.delivered_date > po.expected_date)::int AS late,
    s.rating AS supplier_rating,
    hs.prior_on_time_rate,
    po.expected_date - po.order_date AS planned_lead_time,
    po.total_amount,
    COUNT(pi.line_no) AS line_count,
    SUM(pi.qty_ordered) AS total_qty,
    EXTRACT(MONTH FROM po.order_date)::int AS order_month,
    MIN(c.name) AS category,
    w.city AS warehouse_city
FROM purchase_order AS po
JOIN supplier AS s USING (supplier_id)
JOIN warehouse AS w USING (warehouse_id)
JOIN po_item AS pi USING (po_id)
JOIN product AS p USING (product_id)
JOIN category AS c USING (category_id)
LEFT JOIN LATERAL (
    SELECT
        AVG(CASE WHEN old.delivered_date <= old.expected_date THEN 1.0 ELSE 0.0 END)
            AS prior_on_time_rate
    FROM purchase_order AS old
    LEFT JOIN supplier_evaluation AS se
        ON se.po_id = old.po_id
       AND se.evaluated_on < po.order_date
    WHERE old.supplier_id = po.supplier_id
      AND old.order_date < po.order_date
      AND old.delivered_date IS NOT NULL
      AND old.delivered_date < po.order_date
) AS hs ON TRUE
WHERE po.delivered_date IS NOT NULL
GROUP BY
    po.po_id, po.order_date, po.delivered_date, po.expected_date,
    s.rating, hs.prior_on_time_rate,
    po.total_amount, w.city
ORDER BY po.order_date, po.po_id
"""

NUMERIC = [
    "supplier_rating",
    "prior_on_time_rate",
    "planned_lead_time",
    "total_amount",
    "line_count",
    "total_qty",
    "order_month",
]
CATEGORICAL = ["category", "warehouse_city"]
FEATURES = NUMERIC + CATEGORICAL


def build_pipeline(model):
    prep = ColumnTransformer(
        [
            (
                "num",
                Pipeline(
                    [
                        ("impute", SimpleImputer(strategy="median")),
                        ("scale", StandardScaler()),
                    ]
                ),
                NUMERIC,
            ),
            (
                "cat",
                Pipeline(
                    [
                        ("impute", SimpleImputer(strategy="most_frequent")),
                        ("onehot", OneHotEncoder(handle_unknown="ignore")),
                    ]
                ),
                CATEGORICAL,
            ),
        ]
    )
    return Pipeline([("prep", prep), ("model", model)])


def _evaluate(y_test, predicted, probability):
    try:
        auc = float(roc_auc_score(y_test, probability)) if y_test.nunique() == 2 else None
    except ValueError:
        auc = None
    return {
        "roc_auc": auc,
        "accuracy": float(accuracy_score(y_test, predicted)),
        "precision": float(precision_score(y_test, predicted, zero_division=0)),
        "recall": float(recall_score(y_test, predicted, zero_division=0)),
        "f1": float(f1_score(y_test, predicted, zero_division=0)),
        "confusion_matrix": confusion_matrix(y_test, predicted, labels=[0, 1]).tolist(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-fraction", type=float, default=0.2)
    args = parser.parse_args()
    if not 0.05 <= args.test_fraction <= 0.4:
        raise ValueError("--test-fraction must be between 0.05 and 0.40")

    frame = read_frame(QUERY)
    if len(frame) < 50 or frame.late.nunique() < 2:
        raise RuntimeError("Need at least 50 delivered POs and both delivery classes to train")

    cut = int(len(frame) * (1 - args.test_fraction))
    train, test = frame.iloc[:cut].copy(), frame.iloc[cut:].copy()
    if train.late.nunique() < 2:
        raise RuntimeError(
            "The chronological training partition contains only one delivery class; "
            "add earlier labelled POs before training."
        )

    X_train, y_train = train[FEATURES], train.late
    X_test, y_test = test[FEATURES], test.late
    candidates = {
        "logistic_regression": build_pipeline(
            LogisticRegression(max_iter=1000, class_weight="balanced")
        ),
        "random_forest": build_pipeline(
            RandomForestClassifier(
                n_estimators=300,
                min_samples_leaf=3,
                class_weight="balanced",
                random_state=42,
                n_jobs=-1,
            )
        ),
    }

    scored = {}
    for name, pipeline in candidates.items():
        pipeline.fit(X_train, y_train)
        probability = pipeline.predict_proba(X_test)[:, 1]
        predicted = (probability >= 0.5).astype(int)
        scored[name] = {
            "pipeline": pipeline,
            **_evaluate(y_test, predicted, probability),
        }

    # Prefer ROC-AUC when mathematically defined; fall back to F1 if the
    # chronological test window has only one class, and preserve that caveat.
    selected_name = max(
        scored,
        key=lambda name: (
            scored[name]["roc_auc"] is not None,
            scored[name]["roc_auc"] if scored[name]["roc_auc"] is not None else scored[name]["f1"],
            scored[name]["f1"],
        ),
    )
    selected = scored[selected_name]
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    joblib.dump(
        {"pipeline": selected["pipeline"], "features": FEATURES, "model_name": selected_name},
        LATE_MODEL,
    )
    metrics = {
        "selected_model": selected_name,
        "train_rows": len(train),
        "test_rows": len(test),
        "test_roc_auc_available": y_test.nunique() == 2,
        "temporal_split": True,
        "feature_notes": [
            "One row per PO; category is MIN(category.name) to align training and inference.",
            "Supplier history includes only completed deliveries before the PO order date.",
            "Supplier rating is read from the supplier master, rather than from optional historical evaluation rows.",
        ],
        "candidates": {
            name: {key: value for key, value in values.items() if key != "pipeline"}
            for name, values in scored.items()
        },
    }
    save_metrics("late_delivery", metrics)
    print(
        f"Saved {LATE_MODEL}; selected {selected_name}; "
        f"test rows={len(test)}; ROC-AUC={selected['roc_auc']}"
    )


if __name__ == "__main__":
    main()
