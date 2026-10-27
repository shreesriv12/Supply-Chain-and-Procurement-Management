from __future__ import annotations
from .groq_client import complete
from .tools import check_stock, compare_suppliers, draft_po
from ..db import run_sql

def run_reorder_agent(product_id: int, warehouse_id: int, requested_by: int, quantity: int | None = None, trigger: str = "manual") -> dict:
    run = run_sql("INSERT INTO agent_run(triggered_by,goal,status) VALUES (%s,%s,'RUNNING') RETURNING run_id", [trigger, f"Assess reorder for product {product_id} in warehouse {warehouse_id}"], app_role="admin")
    run_id = run["data"][0]["run_id"]
    try:
        stock = check_stock(run_id, product_id, warehouse_id)
        if not stock: raise ValueError("Inventory row not found")
        needed = quantity or max(int(stock["reorder_qty"]), int(stock["reorder_level"] - stock["qty_on_hand"] + stock["reorder_qty"]))
        suppliers = compare_suppliers(run_id, product_id)
        if not suppliers: raise ValueError("No active supplier can supply this product")
        draft = draft_po(run_id, product_id, warehouse_id, needed, suppliers[0], requested_by)
        prompt = f"Summarize this procurement recommendation in 3 concise sentences. Stock: {stock}. Selected supplier: {suppliers[0]}. Draft: {draft}. State that manager approval is required."
        try: justification = complete("You are a cautious procurement assistant. Never claim approval or a purchase was sent.", prompt)
        except RuntimeError: justification = f"Draft PO {draft['po_id']} recommends {needed} units from {suppliers[0]['supplier_name']}; manager approval is required."
        return run_sql("UPDATE agent_run SET status='AWAITING_APPROVAL',draft_po_id=%s,justification=%s WHERE run_id=%s RETURNING *", [draft["po_id"], justification, run_id], app_role="admin")
    except Exception as exc:
        run_sql("UPDATE agent_run SET status='FAILED',justification=%s WHERE run_id=%s", [str(exc), run_id], app_role="admin")
        raise
        