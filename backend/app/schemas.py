from __future__ import annotations

from datetime import date
from decimal import Decimal
from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=1, max_length=256)


class SupplierIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    gstin: str | None = Field(default=None, max_length=15)
    email: str | None = Field(default=None, max_length=100)
    phone: str | None = Field(default=None, max_length=20)
    city: str | None = Field(default=None, max_length=50)
    country: str = Field(default="India", max_length=50)
    rating: Decimal | None = Field(default=None, ge=0, le=5)


class ProductIn(BaseModel):
    sku: str = Field(min_length=1, max_length=30)
    name: str = Field(min_length=1, max_length=100)
    category_id: int = Field(gt=0)
    unit: str = Field(default="pcs", min_length=1, max_length=15)
    std_cost: Decimal = Field(ge=0)


class InventoryAdjustment(BaseModel):
    warehouse_id: int = Field(gt=0)
    product_id: int = Field(gt=0)
    delta: int


class RequisitionLineIn(BaseModel):
    product_id: int = Field(gt=0)
    qty: int = Field(gt=0)


class RequisitionIn(BaseModel):
    dept_id: int | None = Field(default=None, gt=0)
    items: list[RequisitionLineIn] = Field(min_length=1, max_length=500)


class ApprovalIn(BaseModel):
    approver_id: int = Field(gt=0)


class CreatePoIn(BaseModel):
    supplier_id: int = Field(gt=0)
    warehouse_id: int = Field(gt=0)


class ReceiptIn(BaseModel):
    lines: list[dict] = Field(min_length=1, max_length=500)
    # Supplying the same reference on a retry makes receipt submission idempotent.
    ref_no: str | None = Field(default=None, min_length=1, max_length=40)


class PaymentIn(BaseModel):
    amount: Decimal = Field(gt=0)
    method: str = Field(pattern=r"^(NEFT|UPI|CHEQUE|CARD)$")
