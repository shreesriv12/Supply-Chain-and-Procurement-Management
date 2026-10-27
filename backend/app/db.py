"""Small raw-SQL layer. Every API query is timed and returned to the UI."""
from __future__ import annotations

import os
from time import perf_counter
from typing import Any, Iterable

from psycopg import sql
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://scm_admin:scm_admin@localhost:5432/scm")
ROLE_MAP = {
    "admin": "app_admin", "procurement_mgr": "app_procurement", "warehouse_staff": "app_warehouse",
    "finance": "app_finance", "viewer": "app_viewer", "nl_readonly": "nl_readonly",
}
pool = ConnectionPool(conninfo=DATABASE_URL, kwargs={"row_factory": dict_row}, open=False)

def open_pool() -> None:
    if pool.closed:
        pool.open(wait=True)

def close_pool() -> None:
    if not pool.closed:
        pool.close()

def run_sql(query: str, params: Iterable[Any] | None = None, *, app_role: str = "admin") -> dict[str, Any]:
    """Execute one parameterized statement and return the UI SQL-panel contract."""
    if app_role not in ROLE_MAP:
        raise ValueError("Unknown application role")
    values = list(params or [])
    started = perf_counter()
    with pool.connection() as conn, conn.transaction():
        with conn.cursor() as cur:
            cur.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(ROLE_MAP[app_role])))
            cur.execute("SET LOCAL statement_timeout = '5000ms'")
            cur.execute(query, values)
            rows = cur.fetchall() if cur.description else []
            affected = cur.rowcount
    return {
        "data": rows,
        "executed_sql": [query],
        "params": [values],
        "duration_ms": round((perf_counter() - started) * 1000, 2),
        "rows_affected": affected,
    }
