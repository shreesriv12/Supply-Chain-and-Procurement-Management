-- Supply Chain and Procurement Management
-- Reporting views

-- =========================================================
-- 1. LOW-STOCK INVENTORY
-- =========================================================

CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    i.warehouse_id,
    w.name AS warehouse_name,
    i.product_id,
    p.sku,
    p.name AS product_name,
    i.qty_on_hand,
    i.reorder_level,
    i.reorder_qty
FROM inventory AS i
JOIN warehouse AS w
    ON w.warehouse_id = i.warehouse_id
JOIN product AS p
    ON p.product_id = i.product_id
WHERE i.qty_on_hand <= i.reorder_level;


-- =========================================================
-- 2. SUPPLIER PERFORMANCE
-- =========================================================

CREATE OR REPLACE VIEW v_supplier_performance AS
SELECT
    s.supplier_id,
    s.name AS supplier_name,
    s.rating,

    COUNT(se.eval_id) AS evaluated_orders,

    ROUND(
        (
            AVG(
                CASE
                    WHEN se.on_time THEN 1.0
                    ELSE 0.0
                END
            ) * 100
        )::NUMERIC,
        2
    ) AS on_time_rate_pct,

    ROUND(AVG(se.quality_score), 2) AS avg_quality_score,

    ROUND(
        COALESCE(AVG(se.days_late), 0)::NUMERIC,
        2
    ) AS avg_days_late

FROM supplier AS s
LEFT JOIN supplier_evaluation AS se
    ON se.supplier_id = s.supplier_id
GROUP BY
    s.supplier_id,
    s.name,
    s.rating;


-- =========================================================
-- 3. PURCHASE ORDER SUMMARY
-- Aggregate PO items before joining to prevent row multiplication.
-- =========================================================

CREATE OR REPLACE VIEW v_po_summary AS
SELECT
    po.po_id,
    po.req_id,
    po.order_date,
    po.expected_date,
    po.delivered_date,
    po.status,
    po.total_amount,

    s.supplier_id,
    s.name AS supplier_name,

    w.name AS warehouse_name,
    e.name AS created_by_name,

    COALESCE(items.line_count, 0) AS line_count,
    COALESCE(items.total_ordered_qty, 0) AS total_ordered_qty,
    COALESCE(items.total_received_qty, 0) AS total_received_qty

FROM purchase_order AS po
JOIN supplier AS s
    ON s.supplier_id = po.supplier_id
JOIN warehouse AS w
    ON w.warehouse_id = po.warehouse_id
JOIN employee AS e
    ON e.emp_id = po.created_by

LEFT JOIN (
    SELECT
        po_id,
        COUNT(*) AS line_count,
        SUM(qty_ordered) AS total_ordered_qty,
        SUM(qty_received) AS total_received_qty
    FROM po_item
    GROUP BY po_id
) AS items
    ON items.po_id = po.po_id;


-- =========================================================
-- 4. OUTSTANDING INVOICE BALANCES
-- Shows every invoice with a positive outstanding balance,
-- regardless of its current status.
-- =========================================================

CREATE OR REPLACE VIEW v_pending_payments AS
SELECT
    i.invoice_id,
    i.invoice_no,
    i.invoice_date,
    i.due_date,
    i.amount AS invoice_amount,
    i.status,

    s.supplier_id,
    s.name AS supplier_name,

    po.po_id,

    COALESCE(payments.paid_amount, 0)::NUMERIC(14,2)
        AS paid_amount,

    (
        i.amount - COALESCE(payments.paid_amount, 0)
    )::NUMERIC(14,2) AS outstanding_amount

FROM invoice AS i
JOIN supplier AS s
    ON s.supplier_id = i.supplier_id
JOIN purchase_order AS po
    ON po.po_id = i.po_id

LEFT JOIN (
    SELECT
        invoice_id,
        SUM(amount) AS paid_amount
    FROM payment
    GROUP BY invoice_id
) AS payments
    ON payments.invoice_id = i.invoice_id

WHERE i.amount > COALESCE(payments.paid_amount, 0);


-- =========================================================
-- 5. MONTHLY ORDERED SPEND BY CATEGORY
-- Represents the value of ordered quantities, not payments made.
-- =========================================================

CREATE OR REPLACE VIEW v_spend_by_category AS
SELECT
    c.category_id,
    c.name AS category_name,

    DATE_TRUNC('month', po.order_date)::DATE AS month,

    SUM(pi.qty_ordered * pi.unit_price)::NUMERIC(16,2)
        AS spend,

    COUNT(DISTINCT po.po_id) AS po_count

FROM purchase_order AS po
JOIN po_item AS pi
    ON pi.po_id = po.po_id
JOIN product AS pr
    ON pr.product_id = pi.product_id
JOIN category AS c
    ON c.category_id = pr.category_id

WHERE po.status NOT IN ('DRAFT', 'CANCELLED')

GROUP BY
    c.category_id,
    c.name,
    DATE_TRUNC('month', po.order_date)::DATE;
