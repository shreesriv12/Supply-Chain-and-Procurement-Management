"""Run as a separate service: LISTEN low_stock and create approval-only draft POs."""
from __future__ import annotations
import os
from psycopg import connect
from .agent import run_reorder_agent
from ..db import open_pool
def main() -> None:
    open_pool()
    url = os.getenv("DATABASE_URL", "postgresql://scm_admin:scm_admin@localhost:5432/scm")
    with connect(url, autocommit=True) as conn:
        conn.execute("LISTEN low_stock")
        for notification in conn.notifies():
            import json
            payload = json.loads(notification.payload)
            run_reorder_agent(payload["product_id"], payload["warehouse_id"], requested_by=1, trigger="low_stock")
if __name__ == "__main__": main()
