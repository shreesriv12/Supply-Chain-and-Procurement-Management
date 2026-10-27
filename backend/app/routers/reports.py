from fastapi import APIRouter, Depends
from ..auth import current_user
from ..db import run_sql
router = APIRouter(prefix="/reports", tags=["reports"])
@router.get("/spend")
def spend(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_spend_by_category ORDER BY month, category_name", app_role=user["role"])
@router.get("/supplier-performance")
def supplier_performance(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_supplier_performance ORDER BY on_time_rate_pct DESC NULLS LAST", app_role=user["role"])
@router.get("/overdue-payments")
def overdue(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_pending_payments WHERE due_date < CURRENT_DATE AND outstanding_amount > 0 ORDER BY due_date", app_role=user["role"])
