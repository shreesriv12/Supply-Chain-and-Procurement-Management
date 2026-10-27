from fastapi import APIRouter, Depends
from ..auth import current_user
from ..db import run_sql
from ..schemas import PaymentIn
router = APIRouter(prefix="/invoices", tags=["invoices"])
@router.get("")
def list_invoices(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM v_pending_payments ORDER BY due_date", app_role=user["role"])
@router.post("/{invoice_id}/pay")
def pay(invoice_id: int, body: PaymentIn, user: dict = Depends(current_user)):
    return run_sql("CALL sp_pay_invoice(%s,%s,%s)", [invoice_id, body.amount, body.method], app_role=user["role"])
