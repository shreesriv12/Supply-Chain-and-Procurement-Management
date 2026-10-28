-- Supply Chain and Procurement Management
-- Demonstration queries for DBMS assignment requirements


-- =========================================================
-- Q1: FOUR-TABLE JOIN
-- Purchase orders with supplier, warehouse and creator details
-- =========================================================

SELECT
    po.po_id,
    po.order_date,
    s.name AS supplier,
    w.name AS warehouse,
    e.name AS creator,
    po.total_amount
FROM purchase_order AS po
JOIN supplier AS s
    USING (supplier_id)
JOIN warehouse AS w
    USING (warehouse_id)
JOIN employee AS e
    ON e.emp_id = po.created_by;


-- =========================================================
-- Q2: AGGREGATE, GROUP BY AND HAVING
-- Suppliers with more than 100,000 in PO value over six months
-- =========================================================

SELECT
    s.name AS supplier_name,
    SUM(po.total_amount) AS total_spend
FROM supplier AS s
JOIN purchase_order AS po
    USING (supplier_id)
WHERE po.order_date >= CURRENT_DATE - INTERVAL '6 months'
GROUP BY
    s.supplier_id,
    s.name
HAVING SUM(po.total_amount) > 100000;


-- =========================================================
-- Q3: CORRELATED SUBQUERY
-- Supplier prices above the average for the product category
-- =========================================================

SELECT
    p.sku,
    p.name AS product_name,
    sp.unit_price
FROM product AS p
JOIN supplier_product AS sp
    USING (product_id)
WHERE sp.unit_price > (
    SELECT AVG(sp2.unit_price)
    FROM supplier_product AS sp2
    JOIN product AS p2
        USING (product_id)
    WHERE p2.category_id = p.category_id
);


-- =========================================================
-- Q4: NESTED SUBQUERY
-- Suppliers with received orders and no recorded late evaluation
-- =========================================================

SELECT
    s.supplier_id,
    s.name
FROM supplier AS s
WHERE s.supplier_id IN (
    SELECT po.supplier_id
    FROM purchase_order AS po
    WHERE po.status = 'RECEIVED'
)
AND s.supplier_id NOT IN (
    SELECT se.supplier_id
    FROM supplier_evaluation AS se
    WHERE se.on_time = FALSE
);


-- =========================================================
-- Q5: NOT EXISTS
-- Products that have no associated supplier
-- =========================================================

SELECT
    p.product_id,
    p.sku,
    p.name
FROM product AS p
WHERE NOT EXISTS (
    SELECT 1
    FROM supplier_product AS sp
    WHERE sp.product_id = p.product_id
);


-- =========================================================
-- Q6: WINDOW FUNCTION
-- Rank suppliers by on-time performance within each category
-- Each evaluation is counted once per category.
-- =========================================================

WITH supplier_category_evaluations AS (
    SELECT DISTINCT
        se.eval_id,
        c.category_id,
        c.name AS category_name,
        s.supplier_id,
        s.name AS supplier_name,
        se.on_time
    FROM supplier_evaluation AS se
    JOIN supplier AS s
        USING (supplier_id)
    JOIN po_item AS pi
        ON pi.po_id = se.po_id
    JOIN product AS p
        USING (product_id)
    JOIN category AS c
        USING (category_id)
),
supplier_category_rates AS (
    SELECT
        category_id,
        category_name,
        supplier_id,
        supplier_name,
        ROUND(
            AVG(
                CASE
                    WHEN on_time THEN 1.0
                    ELSE 0.0
                END
            ) * 100,
            2
        ) AS on_time_rate_pct
    FROM supplier_category_evaluations
    GROUP BY
        category_id,
        category_name,
        supplier_id,
        supplier_name
)
SELECT
    category_name,
    supplier_name,
    on_time_rate_pct,
    RANK() OVER (
        PARTITION BY category_id
        ORDER BY on_time_rate_pct DESC
    ) AS supplier_rank
FROM supplier_category_rates
ORDER BY
    category_name,
    supplier_rank,
    supplier_name;


-- =========================================================
-- Q7: CTE AND MONTH-OVER-MONTH SPEND
-- FIX: Use month_start consistently instead of month.
-- =========================================================

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month_start,
        SUM(total_amount) AS spend
    FROM purchase_order
    GROUP BY DATE_TRUNC('month', order_date)::DATE
)
SELECT
    month_start,
    spend,
    spend - LAG(spend) OVER (
        ORDER BY month_start
    ) AS mom_change
FROM monthly
ORDER BY month_start;


-- =========================================================
-- Q8: SET OPERATION - UNION
-- Products appearing in low-stock inventory at warehouse 1 or 2
-- =========================================================

SELECT
    product_id,
    product_name
FROM v_low_stock
WHERE warehouse_id = 1

UNION

SELECT
    product_id,
    product_name
FROM v_low_stock
WHERE warehouse_id = 2;


-- =========================================================
-- Q9: LEFT JOIN
-- Purchase orders without an invoice
-- =========================================================

SELECT
    po.po_id,
    po.order_date,
    s.name AS supplier
FROM purchase_order AS po
JOIN supplier AS s
    USING (supplier_id)
LEFT JOIN invoice AS i
    USING (po_id)
WHERE i.invoice_id IS NULL;


-- =========================================================
-- Q10: UPDATE WITH SUBQUERY
-- DEMO ONLY: intentionally commented out.
-- Execute only inside a controlled, reversible transaction.
-- =========================================================

-- BEGIN;
--
-- UPDATE supplier
-- SET status = 'BLOCKED'
-- WHERE supplier_id IN (
--     SELECT supplier_id
--     FROM supplier
--     WHERE rating < 2.0
-- );
--
-- SELECT supplier_id, name, status, rating
-- FROM supplier
-- WHERE rating < 2.0;
--
-- ROLLBACK;