CREATE OR REPLACE PROCEDURE sp_create_po_from_requisition(IN p_req_id INT, IN p_supplier_id INT, IN p_warehouse_id INT, IN p_creator_id INT)
LANGUAGE plpgsql AS $$
DECLARE new_po_id INT; req_status TEXT;
BEGIN
  SELECT status INTO req_status FROM purchase_requisition WHERE req_id = p_req_id FOR UPDATE;
  IF req_status <> 'APPROVED' THEN RAISE EXCEPTION 'Requisition % is not approved', p_req_id; END IF;
  INSERT INTO purchase_order (req_id, supplier_id, warehouse_id, created_by, order_date, expected_date, status)
  VALUES (p_req_id, p_supplier_id, p_warehouse_id, p_creator_id, CURRENT_DATE, CURRENT_DATE + 14, 'DRAFT') RETURNING po_id INTO new_po_id;
  INSERT INTO po_item (po_id, line_no, product_id, qty_ordered, unit_price)
  SELECT new_po_id, row_number() OVER (ORDER BY ri.product_id), ri.product_id, ri.qty, sp.unit_price
  FROM requisition_item ri JOIN supplier_product sp ON sp.product_id = ri.product_id AND sp.supplier_id = p_supplier_id WHERE ri.req_id = p_req_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Supplier % cannot supply the requested products', p_supplier_id; END IF;
  UPDATE purchase_order SET total_amount = (SELECT SUM(qty_ordered * unit_price) FROM po_item WHERE po_id = new_po_id) WHERE po_id = new_po_id;
  UPDATE purchase_requisition SET status = 'CONVERTED' WHERE req_id = p_req_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_approve_po(IN p_po_id INT, IN p_approver_id INT)
LANGUAGE plpgsql AS $$
DECLARE po_total NUMERIC; limit_amount NUMERIC; approver_role TEXT;
BEGIN
  SELECT total_amount INTO po_total FROM purchase_order WHERE po_id = p_po_id FOR UPDATE;
  SELECT approval_limit, role INTO limit_amount, approver_role FROM employee WHERE emp_id = p_approver_id;
  IF po_total IS NULL OR limit_amount IS NULL THEN RAISE EXCEPTION 'PO or approver not found'; END IF;
  IF approver_role <> 'admin' AND po_total > limit_amount THEN RAISE EXCEPTION 'PO total exceeds approver limit'; END IF;
  UPDATE purchase_order SET approved_by = p_approver_id, status = 'APPROVED' WHERE po_id = p_po_id AND status = 'DRAFT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only a DRAFT PO may be approved'; END IF;
END $$;

CREATE OR REPLACE PROCEDURE sp_receive_goods(IN p_po_id INT, IN p_grn_lines JSONB, IN p_emp_id INT)
LANGUAGE plpgsql AS $$
DECLARE receipt_id INT; wh INT; line JSONB;
BEGIN
  SELECT warehouse_id INTO wh FROM purchase_order WHERE po_id = p_po_id FOR UPDATE;
  IF wh IS NULL THEN RAISE EXCEPTION 'PO % not found', p_po_id; END IF;
  INSERT INTO goods_receipt (po_id, warehouse_id, received_by) VALUES (p_po_id, wh, p_emp_id) RETURNING grn_id INTO receipt_id;
  FOR line IN SELECT value FROM jsonb_array_elements(p_grn_lines) LOOP
    INSERT INTO grn_item (grn_id, line_no, po_id, po_line_no, qty_received, qty_rejected)
    VALUES (receipt_id, (line->>'line_no')::INT, p_po_id, (line->>'po_line_no')::INT, (line->>'qty_received')::INT, COALESCE((line->>'qty_rejected')::INT, 0));
  END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE sp_pay_invoice(IN p_invoice_id INT, IN p_amount NUMERIC, IN p_method VARCHAR(15))
LANGUAGE plpgsql AS $$
DECLARE invoice_amount NUMERIC; already_paid NUMERIC; invoice_status TEXT;
BEGIN
  SELECT amount, status INTO invoice_amount, invoice_status FROM invoice WHERE invoice_id = p_invoice_id FOR UPDATE;
  SELECT COALESCE(SUM(amount), 0) INTO already_paid FROM payment WHERE invoice_id = p_invoice_id;
  IF invoice_status <> 'MATCHED' OR NOT fn_three_way_ok((SELECT po_id FROM invoice WHERE invoice_id = p_invoice_id), invoice_amount) THEN RAISE EXCEPTION 'Only three-way MATCHED invoices can be paid'; END IF;
  IF p_amount <= 0 OR already_paid + p_amount > invoice_amount THEN RAISE EXCEPTION 'Payment exceeds invoice balance'; END IF;
  INSERT INTO payment (invoice_id, amount, method) VALUES (p_invoice_id, p_amount, p_method);
  IF already_paid + p_amount = invoice_amount THEN UPDATE invoice SET status = 'PAID' WHERE invoice_id = p_invoice_id; END IF;
END $$;
