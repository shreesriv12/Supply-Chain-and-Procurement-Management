from __future__ import annotations
import re
import sqlglot
from sqlglot import exp
from .groq_client import complete

WHITELISTED_VIEWS = {"v_low_stock", "v_supplier_performance", "v_po_summary", "v_pending_payments", "v_spend_by_category"}
SCHEMA_DESCRIPTION = """
Allowed read-only views:
v_low_stock(warehouse_name, product_name, qty_on_hand, reorder_level, reorder_qty)
v_supplier_performance(supplier_name, rating, evaluated_orders, on_time_rate_pct, avg_quality_score, avg_days_late)
v_po_summary(po_id, order_date, expected_date, delivered_date, status, total_amount, supplier_name, warehouse_name, line_count)
v_pending_payments(invoice_id, invoice_no, due_date, invoice_amount, status, supplier_name, paid_amount, outstanding_amount)
v_spend_by_category(category_name, month, spend, po_count)
"""
SYSTEM = "You translate procurement questions into exactly one PostgreSQL SELECT statement. Use only the listed views and their columns. Never use DDL, DML, comments, or markdown."

def validate_sql(candidate: str) -> str:
    candidate = candidate.strip().strip("`").removeprefix("sql").strip()
    if ";" in candidate.rstrip(";") or re.search(r"--|/\*|\*/", candidate): raise ValueError("Only one comment-free SQL statement is allowed")
    parsed = sqlglot.parse(candidate, read="postgres")
    if len(parsed) != 1: raise ValueError("Exactly one statement is required")
    tree = parsed[0]
    if not isinstance(tree, exp.Query): raise ValueError("Only SELECT queries are allowed")
    forbidden = (exp.Insert, exp.Update, exp.Delete, exp.Drop, exp.Create, exp.Alter, exp.Command)
    if any(isinstance(node, forbidden) for node in tree.walk()): raise ValueError("Write and administration SQL is blocked")
    tables = {table.name.lower() for table in tree.find_all(exp.Table)}
    if not tables or not tables <= WHITELISTED_VIEWS: raise ValueError(f"Only whitelisted views may be queried: {', '.join(sorted(WHITELISTED_VIEWS))}")
    if not tree.args.get("limit"): tree = tree.limit(200)
    return tree.sql(dialect="postgres")

def question_to_sql(question: str) -> str:
    if len(question) > 1000: raise ValueError("Question is too long")
    raw = complete(SYSTEM, f"{SCHEMA_DESCRIPTION}\nQuestion: {question}")
    return validate_sql(raw)
