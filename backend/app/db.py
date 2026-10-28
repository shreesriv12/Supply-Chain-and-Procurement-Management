"""Raw-SQL database layer with per-request SQL-panel metadata."""
from __future__ import annotations
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")
import os
from time import perf_counter
from typing import Any, Iterable

from psycopg import sql
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is required. Configure it through the project-root .env/Compose environment."
    )

ROLE_MAP = {
    "admin": "app_admin",
    "procurement_mgr": "app_procurement",
    "warehouse_staff": "app_warehouse",
    "finance": "app_finance",
    "viewer": "app_viewer",
    "nl_readonly": "nl_readonly",
}
pool = ConnectionPool(
    conninfo=DATABASE_URL,
    kwargs={"row_factory": dict_row},
    open=False,
)


def open_pool() -> None:
    if pool.closed:
        pool.open(wait=True)


def close_pool() -> None:
    if not pool.closed:
        pool.close()


def run_sql(
    query: str,
    params: Iterable[Any] | None = None,
    *,
    app_role: str = "admin",
) -> dict[str, Any]:
    """Execute one parameterized statement in one transaction.

    The displayed query is exactly the SQL text sent to psycopg; parameters are
    returned separately and are not interpolated into a potentially unsafe string.
    A database exception exits the transaction context and rolls the transaction back.
    """
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
