from fastapi import APIRouter, Depends, HTTPException
from ..auth import current_user
from ..db import run_sql
from ..schemas import CreatePoIn, RequisitionIn
router = APIRouter(prefix="/requisitions", tags=["requisitions"])

@router.get("")
def list_requisitions(user: dict = Depends(current_user)):
    return run_sql("SELECT r.*, e.name requested_by_name FROM purchase_requisition r JOIN employee e ON e.emp_id=r.requested_by ORDER BY r.created_at DESC", app_role=user["role"])
@router.post("")
def create_requisition(body: RequisitionIn, user: dict = Depends(current_user)):
    if not body.items: raise HTTPException(422, "At least one item is required")
    header = run_sql("INSERT INTO purchase_requisition (requested_by,dept_id) VALUES (%s,%s) RETURNING req_id", [user["emp_id"], body.dept_id], app_role=user["role"])
    req_id = header["data"][0]["req_id"]
    for line in body.items:
        run_sql("INSERT INTO requisition_item (req_id,product_id,qty) VALUES (%s,%s,%s)", [req_id, line["product_id"], line["qty"]], app_role=user["role"])
    return header
@router.post("/{req_id}/approve")
def approve(req_id: int, user: dict = Depends(current_user)):
    return run_sql("UPDATE purchase_requisition SET status='APPROVED', approved_by=%s WHERE req_id=%s AND status='PENDING' RETURNING *", [user["emp_id"], req_id], app_role=user["role"])
@router.post("/{req_id}/create-po")
def create_po(req_id: int, body: CreatePoIn, user: dict = Depends(current_user)):
    return run_sql("CALL sp_create_po_from_requisition(%s,%s,%s,%s)", [req_id, body.supplier_id, body.warehouse_id, user["emp_id"]], app_role=user["role"])
