# Keys, Functional Dependencies and Normalization

This note distinguishes the **illustrative flat relation** from the **implemented relational schema**. The actual line-item key in this project is `(po_id, line_no)`; a purchase order is allowed to contain the same product on different lines unless an additional business rule says otherwise.

## 1. Important keys in the implemented schema

| Relation | Primary key | Candidate/alternate key or important uniqueness rule |
|---|---|---|
| `department` | `dept_id` | `name` (`UNIQUE NOT NULL`) |
| `employee` | `emp_id` | `email` (`UNIQUE NOT NULL`) |
| `supplier` | `supplier_id` | `gstin` is unique when supplied; because it is nullable, NULL is not an identifying value |
| `category` | `category_id` | `name` (`UNIQUE NOT NULL`) |
| `product` | `product_id` | `sku` (`UNIQUE NOT NULL`) |
| `supplier_product` | `(supplier_id, product_id)` | Associative key for a supplier's product offer |
| `inventory` | `(warehouse_id, product_id)` | One inventory balance per warehouse/product pair |
| `requisition_item` | `(req_id, product_id)` | One requisition line per product |
| `po_item` | `(po_id, line_no)` | A product is not itself the line key; duplicate products can appear on multiple lines |
| `goods_receipt` | `grn_id` | Migration adds optional idempotency reference uniqueness for `(po_id, ref_no)` when `ref_no` is non-NULL |
| `grn_item` | `(grn_id, line_no)` | Receipt-line key |
| `invoice` | `invoice_id` | `(supplier_id, invoice_no)` is unique |
| `payment` | `payment_id` | Payments are append-only in the migration; do not edit historical payments |
| `stock_movement` | `movement_id` | Append-only movement history is preferred to editing past movements |
| `supplier_evaluation` | `eval_id` | `po_id` is unique, so a PO has at most one evaluation |

Foreign keys encode the main workflow from requisition to purchase order, receipt, invoice and payment. The composite foreign keys on `grn_item` enforce that a receipt line and its referenced purchase-order line belong to the same PO.

## 2. Worked flat-sheet example

Consider the assignment's example:

`PO_SHEET(po_id, order_date, supplier_id, supplier_name, supplier_city, warehouse_id, warehouse_city, product_id, product_name, category_name, qty, unit_price)`

For this **illustrative sheet only**, assume one row per distinct product within a PO. Under that assumption, the candidate key is `(po_id, product_id)`. If a PO can repeat the same product on different lines, add `line_no` to the flat relation and use `(po_id, line_no)` as the candidate key, matching the implementation.

Functional dependencies under the one-row-per-product assumption:

- `po_id -> order_date, supplier_id, warehouse_id`
- `supplier_id -> supplier_name, supplier_city`
- `warehouse_id -> warehouse_city`
- `product_id -> product_name, category_name`
- `(po_id, product_id) -> qty, unit_price`

The last FD says the PO/product pair determines the quantity and negotiated unit price for that line. `product_id -> category_name` is shown for compactness; in the actual schema, the more explicit dependency chain is `product_id -> category_id -> category.name`.

## 3. First normal form (1NF)

A row stores one PO line and each field is atomic. Repeating product columns or storing multiple products in a single cell would violate 1NF. This flat sheet is in 1NF under the assumption that each row holds one line.

## 4. Second normal form (2NF)

The key `(po_id, product_id)` is composite. `po_id` alone determines order date, supplier and warehouse; `product_id` alone determines product name and category. These are partial dependencies on parts of the key, so the flat relation is not in 2NF.

Decompose into header and detail relations, for example:

- `purchase_order(po_id, order_date, supplier_id, warehouse_id, ...)`
- `po_item(po_id, line_no, product_id, qty_ordered, unit_price)`
- `product(product_id, sku, name, category_id, ...)`

The implemented `po_item` uses `(po_id, line_no)` rather than `(po_id, product_id)`, because line numbers identify rows even when a product appears more than once.

## 5. Third normal form (3NF)

The flat relation has transitive dependencies:

- `po_id -> supplier_id -> supplier_name, supplier_city`
- `po_id -> warehouse_id -> warehouse_city`
- `product_id -> category_id -> category_name`

Store supplier, warehouse and category descriptive attributes in their own relations and reference them through foreign keys. This removes repeated descriptive data from every PO line. The implemented schema uses `supplier`, `warehouse`, `category`, `product`, `purchase_order` and `po_item` for these roles.

## 6. BCNF

A relation is in BCNF when every non-trivial functional dependency has a superkey as its determinant. Under the stated FDs, the line-level relation is not BCNF because `supplier_id`, `warehouse_id` and `product_id` determine descriptive attributes but are not superkeys of `PO_SHEET`.

After decomposition, `supplier_product(supplier_id, product_id, unit_price, lead_time_days, min_order_qty)` is in BCNF under the dependency set where `(supplier_id, product_id)` determines the offer attributes and no additional non-key determinant is assumed. If the business actually imposes `supplier_id -> lead_time_days`, that FD would violate BCNF in `supplier_product`; split supplier-level lead time into a separate relation only if it is a verified business rule. Do not claim that hypothetical dependency is present in the implemented data model without evidence.

## 7. Integrity versus normalization

Normalization reduces redundancy; it does not by itself enforce workflow rules. PK/FK/UNIQUE/CHECK/NOT NULL constraints protect row integrity. Triggers and procedures enforce cross-row/workflow requirements such as blocked suppliers, approved requisitions, receipt tolerance, stock movement, supplier-price audit, invoice matching and payment ceilings. Validate the live trigger definitions after applying `db/10_fixes.sql`.
