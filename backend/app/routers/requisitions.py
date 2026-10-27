from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException

from ..auth import current_user
from ..db import run_sql
from ..schemas import CreatePoIn, RequisitionIn

router = APIRouter(prefix="/requisitions", tags=["requisitions"])


def _require_procurement_manager(user: dict) -> None:
    if user.get("role") not in {"admin", "procurement_mgr"}:
        raise HTTPException(status_code=403, detail="Procurement manager permission required")


@router.get("")
def list_requisitions(user: dict = Depends(current_user)):
    return run_sql(
        "SELECT r.*, e.name requested_by_name "
        "FROM purchase_requisition r JOIN employee e ON e.emp_id=r.requested_by "
        "ORDER BY r.created_at DESC",
        app_role=user["role"],
    )


@router.post("")
def create_requisition(body: RequisitionIn, user: dict = Depends(current_user)):
    _require_procurement_manager(user)
    # One data-modifying CTE means the header and every item commit or roll back
    # as one PostgreSQL statement. Duplicate products or invalid FKs cannot leave
    # an orphaned requisition header.
    query = """
    WITH new_req AS (
        INSERT INTO purchase_requisition (requested_by, dept_id)
        VALUES (%s, %s)
        RETURNING req_id
    ), new_items AS (
        INSERT INTO requisition_item (req_id, product_id, qty)
        SELECT new_req.req_id, item.product_id, item.qty
        FROM new_req
        CROSS JOIN jsonb_to_recordset(%s::jsonb) AS item(product_id INT, qty INT)
        RETURNING req_id, product_id
    )
    SELECT new_req.req_id, COUNT(new_items.product_id)::INT AS items_created
    FROM new_req
    JOIN new_items USING (req_id)
    GROUP BY new_req.req_id
    """
    lines = [line.model_dump() for line in body.items]
    result = run_sql(
        query,
        [user["emp_id"], body.dept_id, json.dumps(lines)],
        app_role=user["role"],
    )
    if not result["data"]:
        raise HTTPException(status_code=500, detail="Requisition could not be created")
    return result


@router.post("/{req_id}/approve")
def approve(req_id: int, user: dict = Depends(current_user)):
    _require_procurement_manager(user)
    result = run_sql(
        "UPDATE purchase_requisition SET status='APPROVED', approved_by=%s "
        "WHERE req_id=%s AND status='PENDING' RETURNING *",
        [user["emp_id"], req_id],
        app_role=user["role"],
    )
    if not result["data"]:
        raise HTTPException(status_code=409, detail="Requisition not found or no longer pending")
    return result


@router.post("/{req_id}/create-po")
def create_po(req_id: int, body: CreatePoIn, user: dict = Depends(current_user)):
    _require_procurement_manager(user)
    return run_sql(
        "CALL sp_create_po_from_requisition(%s,%s,%s,%s)",
        [req_id, body.supplier_id, body.warehouse_id, user["emp_id"]],
        app_role=user["role"],
    )
