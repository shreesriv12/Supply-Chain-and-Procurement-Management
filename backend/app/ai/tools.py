from __future__ import annotations
import json
from typing import Any
from ..db import run_sql
from ..ml.predict import forecast_demand, late_probability

def _log(run_id: int, tool: str, args: dict, result: Any) -> None:
    run_sql("INSERT INTO agent_tool_call (run_id,tool,args,result) VALUES (%s,%s,%s::jsonb,%s::jsonb)", [run_id, tool, json.dumps(args), json.dumps(result, default=str)], app_role="admin")

def check_stock(run_id: int, product_id: int, warehouse_id: int) -> dict:
    result = run_sql("SELECT i.*,p.name product_name FROM inventory i JOIN product p USING(product_id) WHERE product_id=%s AND warehouse_id=%s", [product_id, warehouse_id], app_role="admin")["data"]
    answer = result[0] if result else {}; _log(run_id, "check_stock", {"product_id": product_id, "warehouse_id": warehouse_id}, answer); return answer

def compare_suppliers(run_id: int, product_id: int) -> list[dict]:
    rows = run_sql("SELECT sp.supplier_id,s.name supplier_name,sp.unit_price,sp.lead_time_days,s.rating,s.status FROM supplier_product sp JOIN supplier s USING(supplier_id) WHERE sp.product_id=%s AND s.status='ACTIVE' ORDER BY sp.unit_price,sp.lead_time_days", [product_id], app_role="admin")["data"]
    _log(run_id, "compare_suppliers", {"product_id": product_id}, rows); return rows

def draft_po(run_id: int, product_id: int, warehouse_id: int, quantity: int, supplier: dict, created_by: int) -> dict:
    header = run_sql("INSERT INTO purchase_order (supplier_id,warehouse_id,created_by,order_date,expected_date,status,total_amount) VALUES (%s,%s,%s,CURRENT_DATE,CURRENT_DATE + %s,'DRAFT',0) RETURNING po_id", [supplier["supplier_id"], warehouse_id, created_by, supplier["lead_time_days"]], app_role="admin")
    po_id = header["data"][0]["po_id"]
    run_sql("INSERT INTO po_item(po_id,line_no,product_id,qty_ordered,unit_price) VALUES (%s,1,%s,%s,%s)", [po_id, product_id, quantity, supplier["unit_price"]], app_role="admin")
    result = run_sql("UPDATE purchase_order SET total_amount=(SELECT qty_ordered*unit_price FROM po_item WHERE po_id=%s AND line_no=1) WHERE po_id=%s RETURNING po_id,status,total_amount", [po_id, po_id], app_role="admin")["data"][0]
    _log(run_id, "draft_po", {"product_id": product_id, "warehouse_id": warehouse_id, "quantity": quantity, "supplier_id": supplier["supplier_id"]}, result); return result
