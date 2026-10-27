-- Demo passwords are intentionally not defined here; provision LOGIN roles securely outside source control.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
CREATE ROLE app_admin NOLOGIN;
CREATE ROLE app_procurement NOLOGIN;
CREATE ROLE app_warehouse NOLOGIN;
CREATE ROLE app_finance NOLOGIN;
CREATE ROLE app_viewer NOLOGIN;
CREATE ROLE nl_readonly NOLOGIN;
GRANT app_admin, app_procurement, app_warehouse, app_finance, app_viewer, nl_readonly TO scm_admin;
GRANT USAGE ON SCHEMA public TO app_admin, app_procurement, app_warehouse, app_finance, app_viewer, nl_readonly;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_admin;
GRANT SELECT, INSERT, UPDATE ON supplier, supplier_contact, product, category, supplier_product, purchase_requisition, requisition_item, purchase_order, po_item TO app_procurement;
GRANT SELECT ON employee, warehouse, invoice, v_low_stock, v_supplier_performance, v_po_summary, v_pending_payments, v_spend_by_category TO app_procurement;
GRANT SELECT, UPDATE ON inventory TO app_warehouse;
GRANT SELECT, INSERT ON goods_receipt, grn_item, stock_movement TO app_warehouse;
GRANT SELECT ON employee, warehouse, purchase_order, po_item, product, v_low_stock, v_po_summary TO app_warehouse;
GRANT SELECT, INSERT, UPDATE ON invoice, payment TO app_finance;
GRANT SELECT ON purchase_order, po_item, supplier, v_pending_payments, v_po_summary TO app_finance;
GRANT SELECT ON v_low_stock, v_supplier_performance, v_po_summary, v_pending_payments, v_spend_by_category TO app_viewer, nl_readonly;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_procurement, app_warehouse, app_finance;
GRANT EXECUTE ON PROCEDURE sp_create_po_from_requisition(INT, INT, INT, INT), sp_approve_po(INT, INT) TO app_procurement;
GRANT EXECUTE ON PROCEDURE sp_receive_goods(INT, JSONB, INT) TO app_warehouse;
GRANT EXECUTE ON PROCEDURE sp_pay_invoice(INT, NUMERIC, VARCHAR) TO app_finance;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;
-- Denied-query demo: SET ROLE app_viewer; DELETE FROM supplier WHERE supplier_id = 1; -- permission denied
