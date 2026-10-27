from fastapi import APIRouter, Depends, HTTPException

from ..auth import current_user
from ..db import run_sql
from ..schemas import InventoryAdjustment

router = APIRouter(prefix="/inventory", tags=["inventory"])


@router.get("")
def list_inventory(user: dict = Depends(current_user)):
    return run_sql(
        "SELECT i.*, p.sku, p.name product_name, w.name warehouse_name "
        "FROM inventory i JOIN product p USING (product_id) "
        "JOIN warehouse w USING (warehouse_id) ORDER BY w.name, p.name",
        app_role=user["role"],
    )


@router.get("/low-stock")
def low_stock(user: dict = Depends(current_user)):
    return run_sql(
        "SELECT * FROM v_low_stock ORDER BY warehouse_name, product_name",
        app_role=user["role"],
    )


@router.post("/adjust")
def adjust_stock(body: InventoryAdjustment, user: dict = Depends(current_user)):
    if body.delta == 0:
        raise HTTPException(status_code=422, detail="Adjustment delta must not be zero")

    # One SQL statement atomically updates the balance and appends the matching
    # movement. An insufficient-stock adjustment returns no row and changes nothing.
    result = run_sql(
        """WITH changed AS (
            UPDATE inventory
               SET qty_on_hand = qty_on_hand + %s
             WHERE warehouse_id = %s
               AND product_id = %s
               AND qty_on_hand + %s >= 0
            RETURNING *
        ), movement AS (
            INSERT INTO stock_movement
                (warehouse_id, product_id, movement_type, qty, ref_type)
            SELECT warehouse_id, product_id,
                   CASE WHEN %s > 0 THEN 'IN' ELSE 'OUT' END,
                   abs(%s), 'ADJUSTMENT'
              FROM changed
            RETURNING movement_id
        )
        SELECT changed.*, movement.movement_id
          FROM changed CROSS JOIN movement""",
        [body.delta, body.warehouse_id, body.product_id, body.delta, body.delta, body.delta],
        app_role=user["role"],
    )
    if not result["data"]:
        raise HTTPException(
            status_code=409,
            detail="Inventory row not found or adjustment would make stock negative",
        )
    return result
