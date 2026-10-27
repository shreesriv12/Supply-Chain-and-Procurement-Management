import json

from fastapi import APIRouter, Depends

from ..auth import current_user
from ..db import run_sql
from ..schemas import ReceiptIn

router = APIRouter(prefix="/orders", tags=["receipts"])


@router.post("/{po_id}/receipts")
def receive(po_id: int, body: ReceiptIn, user: dict = Depends(current_user)):
    return run_sql(
        "CALL sp_receive_goods(%s,%s::jsonb,%s,%s)",
        [po_id, json.dumps(body.lines), user["emp_id"], body.ref_no],
        app_role=user["role"],
    )
