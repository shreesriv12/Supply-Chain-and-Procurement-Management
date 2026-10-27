BEGIN;

-- The original CHECK prevented the documented 105% receiving tolerance.
ALTER TABLE po_item DROP CONSTRAINT IF EXISTS po_item_qty_received_check;
ALTER TABLE po_item DROP CONSTRAINT IF EXISTS chk_po_item_received_nonnegative;
ALTER TABLE po_item ADD CONSTRAINT chk_po_item_received_nonnegative CHECK (qty_received >= 0);

-- idempotent receipts
ALTER TABLE goods_receipt ADD COLUMN IF NOT EXISTS ref_no VARCHAR(40);
CREATE UNIQUE INDEX IF NOT EXISTS uq_grn_po_ref ON goods_receipt(po_id, ref_no) WHERE ref_no IS NOT NULL;

-- shared three-way-match test (2% tolerance)
CREATE OR REPLACE FUNCTION fn_three_way_ok(p_po_id INT, p_amount NUMERIC) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
  SELECT COALESCE((
    SELECT abs(p_amount - po.total_amount) <= po.total_amount * 0.02
       AND (SELECT COALESCE(SUM(LEAST(qty_received, qty_ordered) * unit_price), 0)
            FROM po_item WHERE po_id = po.po_id) >= po.total_amount * 0.98
    FROM purchase_order po WHERE po.po_id = p_po_id), FALSE)
$$;

CREATE OR REPLACE FUNCTION fn_match_invoice() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM purchase_order WHERE po_id = NEW.po_id AND supplier_id = NEW.supplier_id) THEN
    RAISE EXCEPTION 'Invoice supplier % does not match supplier of PO %', NEW.supplier_id, NEW.po_id;
  END IF;
  NEW.status := CASE WHEN fn_three_way_ok(NEW.po_id, NEW.amount) THEN 'MATCHED' ELSE 'DISPUTED' END;
  RETURN NEW;
END $$;

-- receipt checks: GRN/PO consistency, PO status, 105% tolerance
CREATE OR REPLACE FUNCTION fn_check_grn_item() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ordered_qty INT; prev INT; grn_po INT; po_status TEXT;
BEGIN
  SELECT po_id INTO grn_po FROM goods_receipt WHERE grn_id = NEW.grn_id;
  IF grn_po IS DISTINCT FROM NEW.po_id THEN
    RAISE EXCEPTION 'GRN % belongs to PO %, not PO %', NEW.grn_id, grn_po, NEW.po_id;
  END IF;
  SELECT status INTO po_status FROM purchase_order WHERE po_id = NEW.po_id;
  IF po_status NOT IN ('APPROVED','SENT','PARTIAL') THEN
    RAISE EXCEPTION 'PO % has status %; goods cannot be received', NEW.po_id, po_status;
  END IF;
  SELECT qty_ordered, qty_received INTO ordered_qty, prev
  FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PO line (%, %) does not exist', NEW.po_id, NEW.po_line_no; END IF;
  IF NEW.qty_received + NEW.qty_rejected <= 0 THEN RAISE EXCEPTION 'Receipt line must have a quantity'; END IF;
  IF prev + NEW.qty_received > FLOOR(ordered_qty * 1.05) THEN
    RAISE EXCEPTION 'Receipt exceeds the 5%% tolerance for PO %, line %', NEW.po_id, NEW.po_line_no;
  END IF;
  RETURN NEW;
END $$;

-- apply receipt: upsert inventory (row may not exist), dated movement, PO status
CREATE OR REPLACE FUNCTION fn_apply_grn_item() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE wh INT; rdate DATE; prod INT; all_received BOOLEAN;
BEGIN
  SELECT warehouse_id, received_date INTO wh, rdate FROM goods_receipt WHERE grn_id = NEW.grn_id;
  SELECT product_id INTO prod FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  UPDATE po_item SET qty_received = qty_received + NEW.qty_received WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  INSERT INTO inventory(warehouse_id, product_id, qty_on_hand) VALUES (wh, prod, NEW.qty_received)
  ON CONFLICT (warehouse_id, product_id) DO UPDATE SET qty_on_hand = inventory.qty_on_hand + EXCLUDED.qty_on_hand;
  INSERT INTO stock_movement(warehouse_id, product_id, movement_type, qty, moved_at, ref_type, ref_id)
  VALUES (wh, prod, 'IN', NEW.qty_received, rdate::timestamp, 'GRN', NEW.grn_id);
  SELECT bool_and(qty_received >= qty_ordered) INTO all_received FROM po_item WHERE po_id = NEW.po_id;
  UPDATE purchase_order SET status = CASE WHEN all_received THEN 'RECEIVED' ELSE 'PARTIAL' END
  WHERE po_id = NEW.po_id AND status NOT IN ('CANCELLED','CLOSED');
  RETURN NEW;
END $$;

-- payments: enforce match + no overpayment on EVERY insert path
CREATE OR REPLACE FUNCTION fn_check_payment() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inv invoice%ROWTYPE; paid NUMERIC;
BEGIN
  SELECT * INTO inv FROM invoice WHERE invoice_id = NEW.invoice_id FOR UPDATE;
  IF NOT fn_three_way_ok(inv.po_id, inv.amount) THEN
    RAISE EXCEPTION 'Three-way match failed for invoice %; payment blocked', inv.invoice_id;
  END IF;
  SELECT COALESCE(SUM(amount), 0) INTO paid FROM payment WHERE invoice_id = NEW.invoice_id;
  IF paid + NEW.amount > inv.amount THEN
    RAISE EXCEPTION 'Payments (%) would exceed invoice amount (%)', paid + NEW.amount, inv.amount;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_payment_bi ON payment;
CREATE TRIGGER trg_payment_bi BEFORE INSERT ON payment FOR EACH ROW EXECUTE FUNCTION fn_check_payment();

CREATE OR REPLACE FUNCTION fn_mark_paid() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE invoice SET status = 'PAID'
  WHERE invoice_id = NEW.invoice_id AND amount <= (SELECT SUM(amount) FROM payment WHERE invoice_id = NEW.invoice_id);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_payment_ai ON payment;
CREATE TRIGGER trg_payment_ai AFTER INSERT ON payment FOR EACH ROW EXECUTE FUNCTION fn_mark_paid();

CREATE OR REPLACE FUNCTION fn_payment_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Payments are immutable; post a correcting entry instead'; END $$;
DROP TRIGGER IF EXISTS trg_payment_immutable ON payment;
CREATE TRIGGER trg_payment_immutable BEFORE UPDATE OR DELETE ON payment FOR EACH ROW EXECUTE FUNCTION fn_payment_immutable();

-- PO approval: role + limit enforced even for direct UPDATEs
CREATE OR REPLACE FUNCTION fn_check_po_approval() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r TEXT; lim NUMERIC;
BEGIN
  IF OLD.status = 'DRAFT' AND NEW.status NOT IN ('DRAFT','CANCELLED') THEN
    SELECT role, approval_limit INTO r, lim FROM employee WHERE emp_id = NEW.approved_by;
    IF r IS NULL OR r NOT IN ('admin','procurement_mgr') THEN RAISE EXCEPTION 'PO needs an authorised approver'; END IF;
    IF NEW.total_amount > lim THEN RAISE EXCEPTION 'PO total % exceeds approver limit %', NEW.total_amount, lim; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_po_approval ON purchase_order;
CREATE TRIGGER trg_po_approval BEFORE UPDATE OF status, approved_by ON purchase_order FOR EACH ROW EXECUTE FUNCTION fn_check_po_approval();

-- requisition approval: manager/admin, not self
CREATE OR REPLACE FUNCTION fn_check_req_approval() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r TEXT;
BEGIN
  IF NEW.status = 'APPROVED' AND OLD.status = 'PENDING' THEN
    SELECT role INTO r FROM employee WHERE emp_id = NEW.approved_by;
    IF r IS NULL OR r NOT IN ('admin','procurement_mgr') THEN RAISE EXCEPTION 'Requisition needs an authorised approver'; END IF;
    IF NEW.approved_by = NEW.requested_by THEN RAISE EXCEPTION 'Self-approval is not allowed'; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_req_approval ON purchase_requisition;
CREATE TRIGGER trg_req_approval BEFORE UPDATE OF status ON purchase_requisition FOR EACH ROW EXECUTE FUNCTION fn_check_req_approval();

-- keep po.total_amount derived from lines
CREATE OR REPLACE FUNCTION fn_po_total() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pid INT := COALESCE(NEW.po_id, OLD.po_id);
BEGIN
  UPDATE purchase_order SET total_amount = COALESCE((SELECT SUM(qty_ordered*unit_price) FROM po_item WHERE po_id = pid), 0) WHERE po_id = pid;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_po_item_total ON po_item;
CREATE TRIGGER trg_po_item_total AFTER INSERT OR DELETE OR UPDATE OF qty_ordered, unit_price ON po_item FOR EACH ROW EXECUTE FUNCTION fn_po_total();

-- keep agent_run in sync with the PO a manager approves/cancels
CREATE OR REPLACE FUNCTION fn_sync_agent_run() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE agent_run SET status = CASE NEW.status WHEN 'APPROVED' THEN 'APPROVED' ELSE 'REJECTED' END
  WHERE draft_po_id = NEW.po_id AND status = 'AWAITING_APPROVAL';
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_po_agent_sync ON purchase_order;
CREATE TRIGGER trg_po_agent_sync AFTER UPDATE OF status ON purchase_order FOR EACH ROW
WHEN (NEW.status IN ('APPROVED','CANCELLED') AND OLD.status = 'DRAFT') EXECUTE FUNCTION fn_sync_agent_run();

-- other trigger functions must write tables the caller role cannot
ALTER FUNCTION fn_complete_delivery() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_create_low_stock_requisition() SECURITY DEFINER SET search_path = public;

-- procedures
DROP PROCEDURE IF EXISTS sp_receive_goods(INT, JSONB, INT);
CREATE OR REPLACE PROCEDURE sp_receive_goods(IN p_po_id INT, IN p_lines JSONB, IN p_emp_id INT, IN p_ref VARCHAR DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rid INT; wh INT; rec RECORD;
BEGIN
  SELECT warehouse_id INTO wh FROM purchase_order WHERE po_id = p_po_id FOR UPDATE;
  IF wh IS NULL THEN RAISE EXCEPTION 'PO % not found', p_po_id; END IF;
  INSERT INTO goods_receipt(po_id, warehouse_id, received_by, ref_no) VALUES (p_po_id, wh, p_emp_id, p_ref) RETURNING grn_id INTO rid;
  FOR rec IN SELECT value, ordinality FROM jsonb_array_elements(p_lines) WITH ORDINALITY LOOP
    INSERT INTO grn_item(grn_id, line_no, po_id, po_line_no, qty_received, qty_rejected)
    VALUES (rid, rec.ordinality, p_po_id, (rec.value->>'po_line_no')::INT,
            (rec.value->>'qty_received')::INT, COALESCE((rec.value->>'qty_rejected')::INT, 0));
  END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE sp_approve_po(IN p_po_id INT, IN p_approver_id INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE purchase_order SET approved_by = p_approver_id, status = 'APPROVED' WHERE po_id = p_po_id AND status = 'DRAFT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only an existing DRAFT PO may be approved'; END IF;
END $$;

CREATE OR REPLACE PROCEDURE sp_pay_invoice(IN p_invoice_id INT, IN p_amount NUMERIC, IN p_method VARCHAR(15))
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN INSERT INTO payment(invoice_id, amount, method) VALUES (p_invoice_id, p_amount, p_method); END $$;

CREATE OR REPLACE PROCEDURE sp_issue_stock(IN p_wh INT, IN p_prod INT, IN p_qty INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cur INT;
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
  SELECT qty_on_hand INTO cur FROM inventory WHERE warehouse_id = p_wh AND product_id = p_prod FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventory row not found'; END IF;
  IF cur < p_qty THEN RAISE EXCEPTION 'Insufficient stock: % available, % requested', cur, p_qty; END IF;
  UPDATE inventory SET qty_on_hand = qty_on_hand - p_qty WHERE warehouse_id = p_wh AND product_id = p_prod;
  INSERT INTO stock_movement(warehouse_id, product_id, movement_type, qty, ref_type) VALUES (p_wh, p_prod, 'OUT', p_qty, 'ISSUE');
END $$;

CREATE OR REPLACE PROCEDURE sp_rematch_invoice(IN p_invoice_id INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE invoice SET status = CASE WHEN fn_three_way_ok(po_id, amount) THEN 'MATCHED' ELSE 'DISPUTED' END
  WHERE invoice_id = p_invoice_id AND status IN ('PENDING','DISPUTED','MATCHED');
END $$;

-- least privilege: procedures were executable by PUBLIC
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE sp_create_po_from_requisition(INT,INT,INT,INT) TO app_procurement;
GRANT EXECUTE ON PROCEDURE sp_approve_po(INT,INT) TO app_procurement;
GRANT EXECUTE ON PROCEDURE sp_receive_goods(INT,JSONB,INT,VARCHAR) TO app_warehouse;
GRANT EXECUTE ON PROCEDURE sp_issue_stock(INT,INT,INT) TO app_warehouse;
GRANT EXECUTE ON PROCEDURE sp_pay_invoice(INT,NUMERIC,VARCHAR), sp_rematch_invoice(INT) TO app_finance;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO app_admin;

-- read access for joins; password hash stays hidden
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_procurement, app_warehouse, app_finance, app_viewer;
REVOKE SELECT ON employee FROM app_procurement, app_warehouse, app_finance, app_viewer;
GRANT SELECT (emp_id, name, email, role, dept_id, approval_limit) ON employee
  TO app_procurement, app_warehouse, app_finance, app_viewer;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM nl_readonly;
GRANT SELECT ON v_low_stock, v_supplier_performance, v_po_summary, v_pending_payments, v_spend_by_category TO nl_readonly;
GRANT INSERT ON prediction TO app_procurement;
GRANT INSERT ON audit_log TO app_procurement, app_finance;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_procurement, app_warehouse, app_finance;



-- Enforce approver authorization and limits on both direct INSERT and UPDATE paths.
CREATE OR REPLACE FUNCTION fn_check_po_approval() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE approver_role TEXT; approver_limit NUMERIC;
BEGIN
  IF NEW.status IN ('APPROVED','SENT','PARTIAL','RECEIVED','CLOSED') THEN
    SELECT role, approval_limit INTO approver_role, approver_limit
    FROM employee WHERE emp_id = NEW.approved_by;
    IF approver_role IS NULL OR approver_role NOT IN ('admin','procurement_mgr') THEN
      RAISE EXCEPTION 'PO needs an authorized manager/admin approver';
    END IF;
    IF approver_role <> 'admin' AND NEW.total_amount > approver_limit THEN
      RAISE EXCEPTION 'PO total % exceeds approver limit %', NEW.total_amount, approver_limit;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_po_approval ON purchase_order;
CREATE TRIGGER trg_po_approval BEFORE INSERT OR UPDATE OF status, approved_by, total_amount
ON purchase_order FOR EACH ROW EXECUTE FUNCTION fn_check_po_approval();

-- Block direct approval of requisitions by a requester or unauthorized employee.
CREATE OR REPLACE FUNCTION fn_check_req_approval() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE approver_role TEXT;
BEGIN
  IF NEW.status = 'APPROVED'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'APPROVED'
          OR OLD.approved_by IS DISTINCT FROM NEW.approved_by) THEN
    SELECT role INTO approver_role FROM employee WHERE emp_id = NEW.approved_by;
    IF approver_role IS NULL OR approver_role NOT IN ('admin','procurement_mgr') THEN
      RAISE EXCEPTION 'Requisition needs an authorized manager/admin approver';
    END IF;
    IF NEW.approved_by = NEW.requested_by THEN
      RAISE EXCEPTION 'Self-approval is not allowed';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_req_approval ON purchase_requisition;
CREATE TRIGGER trg_req_approval BEFORE INSERT OR UPDATE OF status, approved_by
ON purchase_requisition FOR EACH ROW EXECUTE FUNCTION fn_check_req_approval();

-- Keep received quantities controlled by the receipt trigger, including direct SQL.
CREATE OR REPLACE FUNCTION fn_guard_qty_received_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.qty_received <> 0 THEN
      RAISE EXCEPTION 'New PO lines must start with qty_received = 0; use the goods-receipt workflow';
    END IF;
    RETURN NEW;
  END IF;
  IF current_user NOT IN ('scm_admin','postgres') THEN
    RAISE EXCEPTION 'qty_received is maintained by the goods-receipt workflow';
  END IF;
  IF NEW.qty_received > FLOOR(NEW.qty_ordered * 1.05) THEN
    RAISE EXCEPTION 'Received quantity exceeds the allowed 105%% of ordered quantity';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_po_item_qty_received_guard ON po_item;
CREATE TRIGGER trg_po_item_qty_received_guard BEFORE INSERT OR UPDATE OF qty_received ON po_item
FOR EACH ROW EXECUTE FUNCTION fn_guard_qty_received_update();

-- Rejected-only receipt lines must not create an invalid zero-quantity stock movement.
CREATE OR REPLACE FUNCTION fn_apply_grn_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE wh INT; rdate DATE; prod INT; all_received BOOLEAN;
BEGIN
  SELECT warehouse_id, received_date INTO wh, rdate FROM goods_receipt WHERE grn_id = NEW.grn_id;
  SELECT product_id INTO prod FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  UPDATE po_item SET qty_received = qty_received + NEW.qty_received
  WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  INSERT INTO inventory(warehouse_id, product_id, qty_on_hand)
  VALUES (wh, prod, NEW.qty_received)
  ON CONFLICT (warehouse_id, product_id)
  DO UPDATE SET qty_on_hand = inventory.qty_on_hand + EXCLUDED.qty_on_hand;
  IF NEW.qty_received > 0 THEN
    INSERT INTO stock_movement(warehouse_id, product_id, movement_type, qty, moved_at, ref_type, ref_id)
    VALUES (wh, prod, 'IN', NEW.qty_received, rdate::timestamp, 'GRN', NEW.grn_id);
  END IF;
  SELECT bool_and(qty_received >= qty_ordered) INTO all_received
  FROM po_item WHERE po_id = NEW.po_id;
  UPDATE purchase_order
  SET status = CASE WHEN all_received THEN 'RECEIVED' ELSE 'PARTIAL' END
  WHERE po_id = NEW.po_id AND status NOT IN ('CANCELLED','CLOSED');
  RETURN NEW;
END $$;

-- A posted receipt is immutable: corrections require an explicit compensating operation.
CREATE OR REPLACE FUNCTION fn_grn_item_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Posted receipt lines are immutable; use a compensating correction';
END $$;
DROP TRIGGER IF EXISTS trg_grn_item_immutable ON grn_item;
CREATE TRIGGER trg_grn_item_immutable BEFORE UPDATE OR DELETE ON grn_item
FOR EACH ROW EXECUTE FUNCTION fn_grn_item_immutable();

-- Keep the PO price total correct if a draft line is inserted, deleted, or moved.
CREATE OR REPLACE FUNCTION fn_po_total() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE old_po INT; new_po INT;
BEGIN
  IF TG_OP <> 'INSERT' THEN old_po := OLD.po_id; END IF;
  IF TG_OP <> 'DELETE' THEN new_po := NEW.po_id; END IF;
  IF old_po IS NOT NULL THEN
    UPDATE purchase_order SET total_amount = COALESCE(
      (SELECT SUM(qty_ordered * unit_price) FROM po_item WHERE po_id = old_po), 0)
    WHERE po_id = old_po;
  END IF;
  IF new_po IS NOT NULL AND new_po IS DISTINCT FROM old_po THEN
    UPDATE purchase_order SET total_amount = COALESCE(
      (SELECT SUM(qty_ordered * unit_price) FROM po_item WHERE po_id = new_po), 0)
    WHERE po_id = new_po;
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_po_item_total ON po_item;
CREATE TRIGGER trg_po_item_total AFTER INSERT OR DELETE OR UPDATE OF po_id, line_no, product_id, qty_ordered, unit_price
ON po_item FOR EACH ROW EXECUTE FUNCTION fn_po_total();

-- PO line definitions may change only while a PO remains a draft. Receipt-driven
-- qty_received updates are intentionally not listed in this trigger's UPDATE OF.
CREATE OR REPLACE FUNCTION fn_po_line_draft_only() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE old_status TEXT; new_status TEXT;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    SELECT status INTO old_status FROM purchase_order WHERE po_id = OLD.po_id FOR UPDATE;
    IF old_status IS DISTINCT FROM 'DRAFT' THEN
      RAISE EXCEPTION 'PO lines can be edited only while the PO is DRAFT';
    END IF;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    SELECT status INTO new_status FROM purchase_order WHERE po_id = NEW.po_id FOR UPDATE;
    IF new_status IS DISTINCT FROM 'DRAFT' THEN
      RAISE EXCEPTION 'PO lines can be edited only while the PO is DRAFT';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
DROP TRIGGER IF EXISTS trg_po_line_draft_only ON po_item;
CREATE TRIGGER trg_po_line_draft_only BEFORE INSERT OR DELETE OR UPDATE OF po_id, line_no, product_id, qty_ordered, unit_price
ON po_item FOR EACH ROW EXECUTE FUNCTION fn_po_line_draft_only();

-- One procurement request must not be converted into multiple purchase orders.
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_order_one_per_requisition
ON purchase_order(req_id) WHERE req_id IS NOT NULL;


COMMIT;