# ER/EER Model Description

The model represents the procure-to-pay lifecycle. `Department` employs `Employee`; an employee raises a `PurchaseRequisition`, which contains `RequisitionItem` product lines. An approved requisition becomes a `PurchaseOrder` issued to one `Supplier` and delivered to one `Warehouse`. A PO has `PO_Item` lines, each referencing a product.

`Supplier` and `Product` have a many-to-many relationship implemented by `SupplierProduct`, which records price, lead time, and minimum order quantity. `Warehouse` and `Product` similarly have a many-to-many relationship implemented by `Inventory`, which stores stock and reorder thresholds. `StockMovement` records inbound and outbound quantities against inventory.

A `GoodsReceipt` belongs to a PO and has `GRN_Item` lines linked to PO lines. A PO may receive multiple `Invoice` records; each invoice may receive one or more `Payment` records. A received PO has one `SupplierEvaluation`, while `AuditLog` captures price modifications.

The optional EER specialization is represented through the `employee.role` discriminator. It is disjoint and total: every employee has exactly one allowed role, including procurement manager, warehouse staff, finance officer, viewer, or administrator.

The visual relationship map is available in [er_diagram.svg](er_diagram.svg).
