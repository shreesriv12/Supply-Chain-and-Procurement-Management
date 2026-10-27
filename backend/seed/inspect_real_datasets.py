"""Create a compact reproducible profile for external datasets kept in datasets/."""
from __future__ import annotations
import json
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]; DATA = ROOT / "datasets"; OUTPUT = ROOT / "docs" / "real_dataset_profile.json"
FILES = ["DataCoSupplyChainDataset.csv", "olist_orders_dataset.csv", "olist_order_items_dataset.csv", "olist_order_payments_dataset.csv", "olist_products_dataset.csv", "olist_sellers_dataset.csv", "sales_train_validation.csv", "calendar.csv"]
def main() -> None:
    profile = {}
    for name in FILES:
        path = DATA / name
        if path.exists():
            sample = pd.read_csv(path, nrows=5, encoding="latin-1" if name.startswith("DataCo") else "utf-8")
            profile[name] = {"bytes": path.stat().st_size, "columns": list(sample.columns), "sample_rows": len(sample)}
    OUTPUT.write_text(json.dumps(profile, indent=2), encoding="utf-8"); print(f"Wrote {OUTPUT}")
if __name__ == "__main__": main()
