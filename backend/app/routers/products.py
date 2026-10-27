from fastapi import APIRouter, Depends, Query
from ..auth import current_user
from ..db import run_sql
from ..schemas import ProductIn
router = APIRouter(prefix="/products", tags=["products"])

@router.get("")
def list_products(search: str | None = Query(default=None), user: dict = Depends(current_user)):
    return run_sql("SELECT p.*, c.name AS category_name FROM product p JOIN category c USING (category_id) WHERE (%s::text IS NULL OR p.name ILIKE '%%' || %s || '%%' OR p.sku ILIKE '%%' || %s || '%%') ORDER BY p.name", [search, search, search], app_role=user["role"])
@router.post("")
def create_product(item: ProductIn, user: dict = Depends(current_user)):
    return run_sql("INSERT INTO product (sku,name,category_id,unit,std_cost) VALUES (%s,%s,%s,%s,%s) RETURNING *", list(item.model_dump().values()), app_role=user["role"])
@router.put("/{product_id}")
def update_product(product_id: int, item: ProductIn, user: dict = Depends(current_user)):
    return run_sql("UPDATE product SET sku=%s,name=%s,category_id=%s,unit=%s,std_cost=%s WHERE product_id=%s RETURNING *", [*item.model_dump().values(), product_id], app_role=user["role"])
