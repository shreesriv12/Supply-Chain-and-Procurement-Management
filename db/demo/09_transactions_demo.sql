-- Run labelled Session A and Session B blocks in separate psql sessions.
-- 1. Atomic rollback: the second line breaches the 5% tolerance; no GRN persists.
BEGIN;
CALL sp_receive_goods(1, '[{"line_no":1,"po_line_no":1,"qty_received":1},{"line_no":2,"po_line_no":2,"qty_received":999999}]'::jsonb, 3);
ROLLBACK;

-- 2. CHECK consistency: UPDATE inventory SET qty_on_hand = -1 WHERE warehouse_id=1 AND product_id=1; -- rejected
-- 3. Lost update illustration (do not use in application code):
-- Session A: BEGIN; SELECT qty_on_hand FROM inventory WHERE warehouse_id=1 AND product_id=2; -- read N
-- Session B: BEGIN; SELECT qty_on_hand FROM inventory WHERE warehouse_id=1 AND product_id=2; UPDATE inventory SET qty_on_hand=qty_on_hand-5 WHERE warehouse_id=1 AND product_id=2; COMMIT;
-- Session A: UPDATE inventory SET qty_on_hand=<N-5> WHERE warehouse_id=1 AND product_id=2; COMMIT; -- overwrites B
-- Fixed pattern, in both sessions: BEGIN; SELECT qty_on_hand FROM inventory WHERE warehouse_id=1 AND product_id=2 FOR UPDATE; UPDATE inventory SET qty_on_hand=qty_on_hand-5 WHERE warehouse_id=1 AND product_id=2; COMMIT;

-- 4. Isolation: Session A: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM purchase_order; -- Session B inserts and commits; A repeats SELECT and sees the original count.
-- 5. Deadlock: A locks inventory (1,1), B locks (1,2), then each attempts the other's row. PostgreSQL aborts one. Fix: always lock rows in (warehouse_id, product_id) order.
