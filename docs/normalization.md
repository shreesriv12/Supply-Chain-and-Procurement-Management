# Normalization and Key Analysis

## Core keys

| Relation | Primary key | Additional candidate key |
| --- | --- | --- |
| `department` | `dept_id` | `name` |
| `employee` | `emp_id` | `email` |
| `supplier` | `supplier_id` | `gstin` |
| `product` | `product_id` | `sku` |
| `invoice` | `invoice_id` | (`supplier_id`, `invoice_no`) |
| `supplier_product` | (`supplier_id`, `product_id`) | - |
| `inventory` | (`warehouse_id`, `product_id`) | - |
| `requisition_item` | (`req_id`, `product_id`) | - |
| `po_item` | (`po_id`, `line_no`) | - |
| `grn_item` | (`grn_id`, `line_no`) | - |

Foreign keys represent the procure-to-pay chain: requisition -> purchase order -> goods receipt and invoice -> payment. Product, supplier, warehouse, employee, category, and department are independent master data relations referenced from the transaction relations.

## Worked normalization example

Consider an initial flat relation:

`PO_SHEET(po_id, order_date, supplier_id, supplier_name, supplier_city, warehouse_id, warehouse_city, product_id, product_name, category_name, qty, unit_price)`

Functional dependencies are:

- `po_id -> order_date, supplier_id, warehouse_id`
- `supplier_id -> supplier_name, supplier_city`
- `warehouse_id -> warehouse_city`
- `product_id -> product_name, category_name`
- `(po_id, product_id) -> qty, unit_price`

The candidate key is (`po_id`, `product_id`).

### First normal form

Each row represents one PO line and each attribute is atomic. There are no repeating product columns, so the relation is in 1NF.

### Second normal form

The composite key produces partial dependencies: `po_id` determines order header details, and `product_id` determines product details. Decompose into `purchase_order(po_id, order_date, supplier_id, warehouse_id)`, `product(product_id, product_name, category_id)`, and `po_item(po_id, line_no, product_id, qty_ordered, unit_price)`.

### Third normal form

Transitive dependencies remain in the header: `po_id -> supplier_id -> supplier_name, supplier_city` and `po_id -> warehouse_id -> warehouse_city`. Move these details into `supplier` and `warehouse`. Category details are similarly separated from `product`. The implemented schema has no non-key attribute depending transitively on a key.

### BCNF check

`supplier_product(supplier_id, product_id, unit_price, lead_time_days, min_order_qty)` is in BCNF because its only determinant is (`supplier_id`, `product_id`), which is a key. If `supplier_id -> lead_time_days` were a true business rule, it would violate BCNF because `supplier_id` is not a superkey; the correction would be a separate `supplier_lead_time(supplier_id, lead_time_days)` relation.

## Integrity enforcement

Normalization reduces redundancy; database constraints preserve correctness. The implementation uses PK/FK/UNIQUE/CHECK/NOT NULL constraints plus triggers for blocked suppliers, receipt tolerance, stock movement, price audit, low-stock requisitions, invoice matching, and delivery evaluation.
