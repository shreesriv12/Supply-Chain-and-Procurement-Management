from __future__ import annotations
from datetime import date
from decimal import Decimal
from pydantic import BaseModel, Field

class LoginRequest(BaseModel):
    email: str
    password: str

class SupplierIn(BaseModel):
    name: str
    gstin: str | None = None
    email: str | None = None
    phone: str | None = None
    city: str | None = None
    country: str = "India"
    rating: Decimal | None = Field(default=None, ge=0, le=5)

class ProductIn(BaseModel):
    sku: str
    name: str
    category_id: int
    unit: str = "pcs"
    std_cost: Decimal = Field(ge=0)

class InventoryAdjustment(BaseModel):
    warehouse_id: int
    product_id: int
    delta: int

class RequisitionIn(BaseModel):
    dept_id: int | None = None
    items: list[dict]

class ApprovalIn(BaseModel):
    approver_id: int

class CreatePoIn(BaseModel):
    supplier_id: int
    warehouse_id: int

class ReceiptIn(BaseModel):
    lines: list[dict]

class PaymentIn(BaseModel):
    amount: Decimal = Field(gt=0)
    method: str
