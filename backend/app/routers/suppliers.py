from fastapi import APIRouter, Depends, Query
from ..auth import current_user
from ..db import run_sql
from ..schemas import SupplierIn

router = APIRouter(prefix="/suppliers", tags=["suppliers"])

@router.get("")
def list_suppliers(search: str | None = Query(default=None), user: dict = Depends(current_user)):
    return run_sql("SELECT supplier_id, name, gstin, email, phone, city, country, status, rating, created_at FROM supplier WHERE (%s IS NULL OR name ILIKE '%%' || %s || '%%') ORDER BY name", [search, search], app_role=user["role"])

@router.post("")
def create_supplier(item: SupplierIn, user: dict = Depends(current_user)):
    return run_sql("INSERT INTO supplier (name, gstin, email, phone, city, country, rating) VALUES (%s,%s,%s,%s,%s,%s,%s) RETURNING *", list(item.model_dump().values()), app_role=user["role"])

@router.put("/{supplier_id}")
def update_supplier(supplier_id: int, item: SupplierIn, user: dict = Depends(current_user)):
    return run_sql("UPDATE supplier SET name=%s,gstin=%s,email=%s,phone=%s,city=%s,country=%s,rating=%s WHERE supplier_id=%s RETURNING *", [*item.model_dump().values(), supplier_id], app_role=user["role"])

@router.delete("/{supplier_id}")
def delete_supplier(supplier_id: int, user: dict = Depends(current_user)):
    return run_sql("DELETE FROM supplier WHERE supplier_id=%s RETURNING supplier_id, name", [supplier_id], app_role=user["role"])
