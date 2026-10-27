BEGIN;
-- Procurement maker-checker controls. Idempotent and safe to apply more than once.
CREATE OR REPLACE FUNCTION fn_check_po_approval() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE approver_role TEXT; approver_limit NUMERIC;
BEGIN
  IF NEW.status IN ('APPROVED','SENT','PARTIAL','RECEIVED','CLOSED') THEN
    IF NEW.approved_by IS NULL THEN
      RAISE EXCEPTION 'PO needs an authorized manager/admin approver';
    END IF;
    IF NEW.approved_by = NEW.created_by THEN
      RAISE EXCEPTION 'Purchase-order creator % cannot approve their own PO', NEW.created_by;
    END IF;
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
CREATE TRIGGER trg_po_approval
BEFORE INSERT OR UPDATE OF status, approved_by, total_amount
ON purchase_order FOR EACH ROW EXECUTE FUNCTION fn_check_po_approval();

-- The current local DB uses synthetic seed/demo records. This repairs those
-- fabricated approval fields; do not use this data-repair section on real production history.
UPDATE purchase_requisition r
SET approved_by = (
  SELECT e.emp_id FROM employee e
  WHERE e.emp_id <> r.requested_by
    AND e.role IN ('admin','procurement_mgr')
  ORDER BY CASE WHEN e.role = 'admin' THEN 0 ELSE 1 END, e.emp_id
  LIMIT 1
)
WHERE r.approved_by = r.requested_by
  AND r.approved_by IS NOT NULL;

UPDATE purchase_order po
SET approved_by = (
  SELECT e.emp_id FROM employee e
  WHERE e.emp_id <> po.created_by
    AND e.role IN ('admin','procurement_mgr')
    AND (e.role = 'admin' OR po.total_amount <= e.approval_limit)
  ORDER BY CASE WHEN e.role = 'admin' THEN 0 ELSE 1 END, e.emp_id
  LIMIT 1
)
WHERE po.approved_by = po.created_by
  AND po.approved_by IS NOT NULL;
COMMIT;