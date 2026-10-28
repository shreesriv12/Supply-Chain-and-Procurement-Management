-- Supply Chain and Procurement Management
-- Transaction, constraint, isolation and concurrency demonstrations.
--
-- Sections 1 and 2 run safe self-checks.
-- Sections 3 to 5 are manual, two-session demonstrations.
-- Do not run concurrency examples against production data.


-- =========================================================
-- 1. ATOMIC ROLLBACK: INVALID GOODS RECEIPT
-- =========================================================
-- Attempt a receipt with an excessive quantity on the second line.
-- The database must reject it without retaining partial changes.
-- The test requires PO 1, employee 3 and PO lines 1 and 2.


DO $receipt_atomicity$
DECLARE
    before_grns BIGINT;
    after_grns BIGINT;

    before_movements BIGINT;
    after_movements BIGINT;

    before_item_state JSONB;
    after_item_state JSONB;

    before_inventory_state JSONB;
    after_inventory_state JSONB;

    call_failed BOOLEAN := FALSE;
    error_message TEXT;
    po_warehouse INT;
BEGIN
    -- Verify that the sample data supports this test.
    SELECT warehouse_id
    INTO po_warehouse
    FROM purchase_order
    WHERE po_id = 1
      AND status IN ('APPROVED', 'SENT', 'PARTIAL');

    IF NOT FOUND THEN
        RAISE NOTICE
            'SKIP: No receivable PO is available. Atomic receipt test was skipped without modifying business data.';
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM employee
        WHERE emp_id = 3
    ) THEN
        RAISE EXCEPTION
            'Test prerequisite failed: employee 3 does not exist.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM po_item
        WHERE po_id = 1
          AND line_no IN (1, 2)
    ) <> 2 THEN
        RAISE EXCEPTION
            'Test prerequisite failed: PO 1 must contain lines 1 and 2.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM po_item
        WHERE po_id = 1
          AND line_no = 1
          AND qty_received + 1 > FLOOR(qty_ordered * 1.05)
    ) THEN
        RAISE EXCEPTION
            'Test prerequisite failed: PO 1 line 1 cannot receive one additional unit.';
    END IF;

    -- Capture the state before the invalid operation.
    SELECT COUNT(*)
    INTO before_grns
    FROM goods_receipt
    WHERE po_id = 1;

    SELECT COUNT(*)
    INTO before_movements
    FROM stock_movement
    WHERE ref_type = 'GRN'
      AND ref_id IN (
          SELECT grn_id
          FROM goods_receipt
          WHERE po_id = 1
      );

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'line_no', line_no,
                'qty_received', qty_received
            )
            ORDER BY line_no
        ),
        '[]'::JSONB
    )
    INTO before_item_state
    FROM po_item
    WHERE po_id = 1;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'product_id', product_id,
                'qty_on_hand', qty_on_hand
            )
            ORDER BY product_id
        ),
        '[]'::JSONB
    )
    INTO before_inventory_state
    FROM inventory
    WHERE warehouse_id = po_warehouse
      AND product_id IN (
          SELECT product_id
          FROM po_item
          WHERE po_id = 1
      );

    -- The first line is valid. The second intentionally exceeds tolerance.
    BEGIN
        CALL sp_receive_goods(
            1,
            '[
                {"po_line_no": 1, "qty_received": 1},
                {"po_line_no": 2, "qty_received": 999999}
            ]'::JSONB,
            3
        );

    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;

        -- Do not treat an unrelated failure as a successful test.
        IF POSITION('Receipt exceeds the 5%' IN error_message) <> 1 THEN
            RAISE EXCEPTION
                'Unexpected error during atomicity test: %',
                error_message;
        END IF;

        call_failed := TRUE;

        RAISE NOTICE
            'Expected receiving-tolerance rejection: %',
            error_message;
    END;

    IF NOT call_failed THEN
        RAISE EXCEPTION
            'TEST FAILED: the invalid receipt was unexpectedly accepted.';
    END IF;

    -- Verify that the rejected operation left no partial changes.
    SELECT COUNT(*)
    INTO after_grns
    FROM goods_receipt
    WHERE po_id = 1;

    SELECT COUNT(*)
    INTO after_movements
    FROM stock_movement
    WHERE ref_type = 'GRN'
      AND ref_id IN (
          SELECT grn_id
          FROM goods_receipt
          WHERE po_id = 1
      );

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'line_no', line_no,
                'qty_received', qty_received
            )
            ORDER BY line_no
        ),
        '[]'::JSONB
    )
    INTO after_item_state
    FROM po_item
    WHERE po_id = 1;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'product_id', product_id,
                'qty_on_hand', qty_on_hand
            )
            ORDER BY product_id
        ),
        '[]'::JSONB
    )
    INTO after_inventory_state
    FROM inventory
    WHERE warehouse_id = po_warehouse
      AND product_id IN (
          SELECT product_id
          FROM po_item
          WHERE po_id = 1
      );

    IF before_grns IS DISTINCT FROM after_grns
       OR before_movements IS DISTINCT FROM after_movements
       OR before_item_state IS DISTINCT FROM after_item_state
       OR before_inventory_state IS DISTINCT FROM after_inventory_state
    THEN
        RAISE EXCEPTION
            'TEST FAILED: database state changed after receipt rejection.';
    END IF;

    RAISE NOTICE
        'PASS: invalid receipt rejected; no partial receipt, stock movement, received quantity or inventory changes persisted.';
END
$receipt_atomicity$;


-- =========================================================
-- 2. CHECK CONSTRAINT: INVENTORY CANNOT BECOME NEGATIVE
-- =========================================================
-- This test attempts an invalid update, catches the expected
-- CHECK violation, and verifies that the original value remains.


DO $inventory_check$
DECLARE
    test_warehouse INT;
    test_product INT;
    before_qty INT;
    after_qty INT;
    update_rejected BOOLEAN := FALSE;
BEGIN
    SELECT warehouse_id, product_id, qty_on_hand
    INTO test_warehouse, test_product, before_qty
    FROM inventory
    ORDER BY warehouse_id, product_id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Test prerequisite failed: inventory has no rows.';
    END IF;

    BEGIN
        UPDATE inventory
        SET qty_on_hand = -1
        WHERE warehouse_id = test_warehouse
          AND product_id = test_product;

    EXCEPTION WHEN check_violation THEN
        update_rejected := TRUE;

        RAISE NOTICE
            'Expected CHECK violation: negative inventory is rejected.';
    END;

    IF NOT update_rejected THEN
        RAISE EXCEPTION
            'TEST FAILED: negative inventory was unexpectedly accepted.';
    END IF;

    SELECT qty_on_hand
    INTO after_qty
    FROM inventory
    WHERE warehouse_id = test_warehouse
      AND product_id = test_product;

    IF before_qty IS DISTINCT FROM after_qty THEN
        RAISE EXCEPTION
            'TEST FAILED: inventory quantity changed after rejected update.';
    END IF;

    RAISE NOTICE
        'PASS: inventory CHECK constraint preserved the original quantity.';
END
$inventory_check$;


-- =========================================================
-- 3. LOST UPDATE: TWO MANUAL SESSIONS
-- =========================================================
-- Documentation only. Use two separate psql sessions with a disposable
-- test row. Both sessions must use the SAME warehouse/product row.
--
-- Illustrative unsafe sequence:
--
-- SESSION A:
-- BEGIN;
-- SELECT qty_on_hand
-- FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 2;
-- -- Record the returned quantity as N. Leave the transaction open.
--
-- SESSION B:
-- BEGIN;
-- UPDATE inventory
-- SET qty_on_hand = qty_on_hand - 5
-- WHERE warehouse_id = 1 AND product_id = 2;
-- COMMIT;
--
-- SESSION A:
-- -- Replace <N_MINUS_5> with the actual numeric result calculated from
-- -- Session A's original read. Do not paste the placeholder literally.
-- UPDATE inventory
-- SET qty_on_hand = <N_MINUS_5>
-- WHERE warehouse_id = 1 AND product_id = 2;
-- COMMIT;
--
-- Explanation:
-- Session A overwrites Session B's change because it writes a value
-- computed from an old, non-locking read.


-- Safer pattern: both sessions lock the row before reading/updating.
--
-- SESSION A or SESSION B:
-- BEGIN;
-- SELECT qty_on_hand
-- FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 2
-- FOR UPDATE;
--
-- UPDATE inventory
-- SET qty_on_hand = qty_on_hand - 5
-- WHERE warehouse_id = 1 AND product_id = 2;
-- COMMIT;
--
-- FOR UPDATE serializes changes to that row. Ensure enough stock exists
-- and use application logic to reject insufficient inventory.


-- =========================================================
-- 4. ISOLATION: REPEATABLE READ
-- =========================================================
-- Run Session A and Session B in separate psql connections.
--
-- SESSION A:
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT COUNT(*) FROM purchase_order;
-- -- Record the count. Keep the transaction open.
--
-- SESSION B:
-- BEGIN;
-- -- Insert a valid, disposable test purchase order using valid FK values,
-- -- or use a controlled test dataset.
-- COMMIT;
--
-- SESSION A:
-- SELECT COUNT(*) FROM purchase_order;
-- -- Under REPEATABLE READ, the count remains as seen by Session A's
-- -- transaction snapshot.
-- COMMIT;
--
-- Clean up test data only after both sessions have completed, if the
-- chosen test setup permits safe cleanup.


-- =========================================================
-- 5. DEADLOCK: OPPOSITE LOCK ORDER
-- =========================================================
-- Documentation only. Use two separate sessions and disposable rows.
--
-- SESSION A:
-- BEGIN;
-- SELECT qty_on_hand FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 1
-- FOR UPDATE;
-- -- After Session B has locked (1, 2), try:
-- SELECT qty_on_hand FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 2
-- FOR UPDATE;
-- -- One transaction will be aborted by PostgreSQL to break the deadlock.
--
-- SESSION B:
-- BEGIN;
-- SELECT qty_on_hand FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 2
-- FOR UPDATE;
-- -- After Session A has locked (1, 1), try:
-- SELECT qty_on_hand FROM inventory
-- WHERE warehouse_id = 1 AND product_id = 1
-- FOR UPDATE;
--
-- Recovery:
-- Roll back the transaction that received the deadlock error.
--
-- Prevention:
-- All code paths should acquire multiple inventory-row locks in a
-- consistent, deterministic order, for example by warehouse_id and then
-- product_id. Do not run this demonstration against business data.