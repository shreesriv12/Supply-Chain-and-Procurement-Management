from fastapi import APIRouter, Depends
from ..auth import current_user
from ..db import run_sql
router = APIRouter(prefix="/orders", tags=["orders"])
@router.get("")
def list_orders(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_po_summary ORDER BY order_date DESC", app_role=user["role"])
@router.get("/{po_id}")
def get_order(po_id: int, user: dict = Depends(current_user)):
    return run_sql("SELECT po.*, json_agg(json_build_object('line_no',pi.line_no,'product_id',pi.product_id,'qty_ordered',pi.qty_ordered,'qty_received',pi.qty_received,'unit_price',pi.unit_price) ORDER BY pi.line_no) lines FROM purchase_order po JOIN po_item pi USING (po_id) WHERE po.po_id=%s GROUP BY po.po_id", [po_id], app_role=user["role"])
@router.post("/{po_id}/approve")
def approve_order(po_id: int, user: dict = Depends(current_user)):
    return run_sql("CALL sp_approve_po(%s,%s)", [po_id, user["emp_id"]], app_role=user["role"])
