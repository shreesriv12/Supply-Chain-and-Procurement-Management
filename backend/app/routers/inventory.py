from fastapi import APIRouter, Depends
from ..auth import current_user
from ..db import run_sql
from ..schemas import InventoryAdjustment
router = APIRouter(prefix="/inventory", tags=["inventory"])

@router.get("")
def list_inventory(user: dict = Depends(current_user)):
    return run_sql("SELECT i.*, p.sku, p.name product_name, w.name warehouse_name FROM inventory i JOIN product p USING (product_id) JOIN warehouse w USING (warehouse_id) ORDER BY w.name, p.name", app_role=user["role"])
@router.get("/low-stock")
def low_stock(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_low_stock ORDER BY warehouse_name, product_name", app_role=user["role"])
@router.post("/adjust")
def adjust_stock(body: InventoryAdjustment, user: dict = Depends(current_user)):
    return run_sql("UPDATE inventory SET qty_on_hand = qty_on_hand + %s WHERE warehouse_id=%s AND product_id=%s AND qty_on_hand + %s >= 0 RETURNING *", [body.delta, body.warehouse_id, body.product_id, body.delta], app_role=user["role"])
