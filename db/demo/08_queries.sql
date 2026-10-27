-- Q1: four-table PO join
SELECT po.po_id, po.order_date, s.name supplier, w.name warehouse, e.name creator, po.total_amount FROM purchase_order po JOIN supplier s USING (supplier_id) JOIN warehouse w USING (warehouse_id) JOIN employee e ON e.emp_id = po.created_by;
-- Q2: aggregate, GROUP BY and HAVING
SELECT s.name, SUM(po.total_amount) total_spend FROM supplier s JOIN purchase_order po USING (supplier_id) WHERE po.order_date >= CURRENT_DATE - INTERVAL '6 months' GROUP BY s.supplier_id, s.name HAVING SUM(po.total_amount) > 100000;
-- Q3: correlated subquery
SELECT p.sku, p.name, sp.unit_price FROM product p JOIN supplier_product sp USING (product_id) WHERE sp.unit_price > (SELECT AVG(sp2.unit_price) FROM supplier_product sp2 JOIN product p2 USING (product_id) WHERE p2.category_id = p.category_id);
-- Q4: nested subquery
SELECT s.supplier_id, s.name FROM supplier s WHERE s.supplier_id IN (SELECT po.supplier_id FROM purchase_order po WHERE po.status = 'RECEIVED') AND s.supplier_id NOT IN (SELECT supplier_id FROM supplier_evaluation WHERE NOT on_time);
-- Q5: NOT EXISTS
SELECT p.product_id, p.sku, p.name FROM product p WHERE NOT EXISTS (SELECT 1 FROM supplier_product sp WHERE sp.product_id = p.product_id);
-- Q6: window function
SELECT category_name, supplier_name, on_time_rate_pct, RANK() OVER (PARTITION BY category_name ORDER BY on_time_rate_pct DESC) supplier_rank FROM (SELECT c.name category_name, s.name supplier_name, AVG(CASE WHEN se.on_time THEN 1.0 ELSE 0 END) * 100 on_time_rate_pct FROM supplier_evaluation se JOIN supplier s USING (supplier_id) JOIN po_item pi ON pi.po_id = se.po_id JOIN product p USING (product_id) JOIN category c USING (category_id) GROUP BY c.name, s.name) ranked;
-- Q7: CTE with month-over-month spend
WITH monthly AS (SELECT date_trunc('month', order_date)::date month, SUM(total_amount) spend FROM purchase_order GROUP BY 1) SELECT month, spend, spend - LAG(spend) OVER (ORDER BY month) mom_change FROM monthly ORDER BY month;
-- Q8: set operation
SELECT product_id, product_name FROM v_low_stock WHERE warehouse_id = 1 UNION SELECT product_id, product_name FROM v_low_stock WHERE warehouse_id = 2;
-- Q9: left join
SELECT po.po_id, po.order_date, s.name supplier FROM purchase_order po JOIN supplier s USING (supplier_id) LEFT JOIN invoice i USING (po_id) WHERE i.invoice_id IS NULL;
-- Q10: update with subquery (run only in a transaction during a demo)
-- UPDATE supplier SET status = 'BLOCKED' WHERE supplier_id IN (SELECT supplier_id FROM supplier WHERE rating < 2.0);
