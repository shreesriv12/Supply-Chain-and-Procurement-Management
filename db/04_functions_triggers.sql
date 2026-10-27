-- Business rules live in PostgreSQL so they apply to every client, not only the web app.
CREATE OR REPLACE FUNCTION fn_check_po() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE req_status TEXT; supplier_status TEXT;
BEGIN
  SELECT status INTO supplier_status FROM supplier WHERE supplier_id = NEW.supplier_id;
  IF supplier_status = 'BLOCKED' THEN RAISE EXCEPTION 'Blocked supplier % cannot receive a PO', NEW.supplier_id; END IF;
  IF NEW.req_id IS NULL THEN
    IF current_user NOT IN ('app_admin', 'scm_admin', 'postgres') THEN RAISE EXCEPTION 'Only an admin can create a PO without a requisition'; END IF;
  ELSE
    SELECT status INTO req_status FROM purchase_requisition WHERE req_id = NEW.req_id;
    IF req_status NOT IN ('APPROVED', 'CONVERTED') THEN RAISE EXCEPTION 'Requisition % must be approved before PO creation', NEW.req_id; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_po_bi BEFORE INSERT OR UPDATE OF supplier_id, req_id ON purchase_order FOR EACH ROW EXECUTE FUNCTION fn_check_po();

CREATE OR REPLACE FUNCTION fn_check_grn_item() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE ordered_qty INT; previously_received INT; receipt_po INT; po_status TEXT;
BEGIN
  SELECT po_id INTO receipt_po FROM goods_receipt WHERE grn_id = NEW.grn_id;
  IF receipt_po IS DISTINCT FROM NEW.po_id THEN RAISE EXCEPTION 'GRN % belongs to PO %, not PO %', NEW.grn_id, receipt_po, NEW.po_id; END IF;
  SELECT status INTO po_status FROM purchase_order WHERE po_id = NEW.po_id;
  IF po_status NOT IN ('APPROVED', 'SENT', 'PARTIAL') THEN RAISE EXCEPTION 'PO % has status % and cannot receive goods', NEW.po_id, po_status; END IF;
  SELECT qty_ordered, qty_received INTO ordered_qty, previously_received
  FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PO line (%, %) does not exist', NEW.po_id, NEW.po_line_no; END IF;
  IF NEW.qty_received + NEW.qty_rejected <= 0 THEN RAISE EXCEPTION 'A receipt line must contain a received or rejected quantity'; END IF;
  IF previously_received + NEW.qty_received > CEIL(ordered_qty * 1.05) THEN
    RAISE EXCEPTION 'Receipt exceeds the 5%% tolerance for PO %, line %', NEW.po_id, NEW.po_line_no;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_po_item_bi BEFORE INSERT ON grn_item FOR EACH ROW EXECUTE FUNCTION fn_check_grn_item();

CREATE OR REPLACE FUNCTION fn_apply_grn_item() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE wh INT; all_received BOOLEAN;
BEGIN
  SELECT warehouse_id INTO wh FROM goods_receipt WHERE grn_id = NEW.grn_id;
  UPDATE po_item SET qty_received = qty_received + NEW.qty_received WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  UPDATE inventory SET qty_on_hand = qty_on_hand + NEW.qty_received WHERE warehouse_id = wh AND product_id =
    (SELECT product_id FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no);
  INSERT INTO stock_movement (warehouse_id, product_id, movement_type, qty, ref_type, ref_id)
  SELECT wh, product_id, 'IN', NEW.qty_received, 'GRN', NEW.grn_id FROM po_item WHERE po_id = NEW.po_id AND line_no = NEW.po_line_no;
  SELECT bool_and(qty_received >= qty_ordered) INTO all_received FROM po_item WHERE po_id = NEW.po_id;
  UPDATE purchase_order SET status = CASE WHEN all_received THEN 'RECEIVED' ELSE 'PARTIAL' END WHERE po_id = NEW.po_id AND status NOT IN ('CANCELLED', 'CLOSED');
  RETURN NEW;
END $$;
CREATE TRIGGER trg_grn_item_ai AFTER INSERT ON grn_item FOR EACH ROW EXECUTE FUNCTION fn_apply_grn_item();

CREATE OR REPLACE FUNCTION fn_audit_supplier_price() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.unit_price IS DISTINCT FROM NEW.unit_price THEN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES ('supplier_product', NEW.supplier_id || ':' || NEW.product_id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_supplier_product_au AFTER UPDATE OF unit_price ON supplier_product FOR EACH ROW EXECUTE FUNCTION fn_audit_supplier_price();

CREATE OR REPLACE FUNCTION fn_create_low_stock_requisition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE requester INT; request_id INT;
BEGIN
  IF NEW.qty_on_hand <= NEW.reorder_level AND (OLD.qty_on_hand > OLD.reorder_level OR TG_OP = 'INSERT') THEN
    IF NOT EXISTS (
      SELECT 1 FROM purchase_requisition r JOIN requisition_item ri USING (req_id)
      WHERE r.source = 'AUTO' AND r.status IN ('PENDING','APPROVED') AND ri.product_id = NEW.product_id
    ) THEN
      SELECT emp_id INTO requester FROM employee WHERE role IN ('procurement_mgr','admin') ORDER BY emp_id LIMIT 1;
      IF requester IS NULL THEN RAISE EXCEPTION 'Cannot create auto requisition: no procurement manager'; END IF;
      INSERT INTO purchase_requisition (requested_by, dept_id, source) VALUES (requester, (SELECT dept_id FROM employee WHERE emp_id = requester), 'AUTO') RETURNING req_id INTO request_id;
      INSERT INTO requisition_item (req_id, product_id, qty) VALUES (request_id, NEW.product_id, NEW.reorder_qty);
      PERFORM pg_notify('low_stock', json_build_object('requisition_id', request_id, 'warehouse_id', NEW.warehouse_id, 'product_id', NEW.product_id)::text);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_inventory_au AFTER UPDATE OF qty_on_hand ON inventory FOR EACH ROW EXECUTE FUNCTION fn_create_low_stock_requisition();

CREATE OR REPLACE FUNCTION fn_three_way_ok(p_po_id INT, p_amount NUMERIC) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT abs(p_amount - po.total_amount) <= po.total_amount * .02
    AND (SELECT COALESCE(SUM(LEAST(qty_received, qty_ordered) * unit_price), 0) FROM po_item WHERE po_id = po.po_id) >= po.total_amount * .98
  FROM purchase_order po WHERE po.po_id = p_po_id), FALSE)
$$;
CREATE OR REPLACE FUNCTION fn_match_invoice() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE po_value NUMERIC; received_value NUMERIC;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM purchase_order WHERE po_id = NEW.po_id AND supplier_id = NEW.supplier_id) THEN RAISE EXCEPTION 'Invoice supplier must match PO supplier'; END IF;
  SELECT total_amount, COALESCE(SUM(LEAST(pi.qty_received, pi.qty_ordered) * pi.unit_price), 0)
  INTO po_value, received_value FROM purchase_order po JOIN po_item pi USING (po_id) WHERE po.po_id = NEW.po_id GROUP BY po.total_amount;
  IF po_value IS NULL OR received_value IS NULL OR received_value < po_value * .98 OR abs(NEW.amount - po_value) > po_value * .02 THEN
    NEW.status := 'DISPUTED';
  ELSE
    NEW.status := 'MATCHED';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_invoice_bi BEFORE INSERT OR UPDATE OF amount, po_id ON invoice FOR EACH ROW EXECUTE FUNCTION fn_match_invoice();

CREATE OR REPLACE FUNCTION fn_check_payment() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE inv invoice%ROWTYPE; paid NUMERIC;
BEGIN
  SELECT * INTO inv FROM invoice WHERE invoice_id = NEW.invoice_id FOR UPDATE;
  IF NOT FOUND OR NOT fn_three_way_ok(inv.po_id, inv.amount) THEN RAISE EXCEPTION 'Three-way match failed; payment blocked'; END IF;
  SELECT COALESCE(SUM(amount), 0) INTO paid FROM payment WHERE invoice_id = NEW.invoice_id;
  IF paid + NEW.amount > inv.amount THEN RAISE EXCEPTION 'Payment exceeds invoice amount'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payment_bi BEFORE INSERT ON payment FOR EACH ROW EXECUTE FUNCTION fn_check_payment();
CREATE OR REPLACE FUNCTION fn_mark_paid() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE invoice SET status = 'PAID' WHERE invoice_id = NEW.invoice_id AND amount <= (SELECT SUM(amount) FROM payment WHERE invoice_id = NEW.invoice_id);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payment_ai AFTER INSERT ON payment FOR EACH ROW EXECUTE FUNCTION fn_mark_paid();

CREATE OR REPLACE FUNCTION fn_complete_delivery() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE is_on_time BOOLEAN;
BEGIN
  IF NEW.status = 'RECEIVED' AND OLD.status IS DISTINCT FROM 'RECEIVED' THEN
    NEW.delivered_date := COALESCE(NEW.delivered_date, CURRENT_DATE);
    is_on_time := NEW.delivered_date <= NEW.expected_date;
    INSERT INTO supplier_evaluation (supplier_id, po_id, on_time, days_late, quality_score)
    VALUES (NEW.supplier_id, NEW.po_id, is_on_time, GREATEST(0, NEW.delivered_date - NEW.expected_date), 4.00)
    ON CONFLICT (po_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_delivered_date BEFORE UPDATE OF status ON purchase_order FOR EACH ROW EXECUTE FUNCTION fn_complete_delivery();
