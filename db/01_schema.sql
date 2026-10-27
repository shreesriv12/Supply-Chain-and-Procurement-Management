-- Supply Chain and Procurement Management
-- Core relational schema
-- PostgreSQL + pgvector

CREATE EXTENSION IF NOT EXISTS vector;

-- =========================================================
-- 1. DEPARTMENTS AND EMPLOYEES
-- =========================================================

CREATE TABLE department (
    dept_id SERIAL PRIMARY KEY,
    name VARCHAR(60) UNIQUE NOT NULL,
    budget NUMERIC(14,2) CHECK (budget >= 0)
);

CREATE TABLE employee (
    emp_id SERIAL PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,

    role VARCHAR(20) NOT NULL
        CHECK (role IN (
            'admin',
            'procurement_mgr',
            'warehouse_staff',
            'finance',
            'viewer'
        )),

    dept_id INT REFERENCES department(dept_id),
    approval_limit NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (approval_limit >= 0)
);

-- =========================================================
-- 2. SUPPLIERS AND CATEGORIES
-- =========================================================

CREATE TABLE supplier (
    supplier_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    gstin VARCHAR(15) UNIQUE,
    email VARCHAR(100),
    phone VARCHAR(20),
    city VARCHAR(50),
    country VARCHAR(50) DEFAULT 'India',

    status VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'BLOCKED')),

    rating NUMERIC(3,2)
        CHECK (rating BETWEEN 0 AND 5),

    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE supplier_contact (
    contact_id SERIAL PRIMARY KEY,
    supplier_id INT NOT NULL
        REFERENCES supplier(supplier_id) ON DELETE CASCADE,

    name VARCHAR(80) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE category (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(60) UNIQUE NOT NULL,
    parent_id INT REFERENCES category(category_id),

    CONSTRAINT chk_category_not_own_parent
        CHECK (parent_id IS NULL OR parent_id <> category_id)
);

CREATE TABLE product (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(30) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL REFERENCES category(category_id),
    unit VARCHAR(15) NOT NULL DEFAULT 'pcs',
    std_cost NUMERIC(12,2) NOT NULL CHECK (std_cost >= 0)
);

CREATE TABLE supplier_product (
    supplier_id INT NOT NULL
        REFERENCES supplier(supplier_id) ON DELETE CASCADE,

    product_id INT NOT NULL
        REFERENCES product(product_id) ON DELETE CASCADE,

    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    lead_time_days INT NOT NULL CHECK (lead_time_days >= 0),
    min_order_qty INT NOT NULL DEFAULT 1 CHECK (min_order_qty > 0),

    PRIMARY KEY (supplier_id, product_id)
);

-- =========================================================
-- 3. WAREHOUSES AND INVENTORY
-- =========================================================

CREATE TABLE warehouse (
    warehouse_id SERIAL PRIMARY KEY,
    name VARCHAR(60) NOT NULL,
    city VARCHAR(50) NOT NULL,
    capacity INT CHECK (capacity > 0)
);

CREATE TABLE inventory (
    warehouse_id INT NOT NULL
        REFERENCES warehouse(warehouse_id),

    product_id INT NOT NULL
        REFERENCES product(product_id),

    qty_on_hand INT NOT NULL DEFAULT 0
        CHECK (qty_on_hand >= 0),

    reorder_level INT NOT NULL DEFAULT 10
        CHECK (reorder_level >= 0),

    reorder_qty INT NOT NULL DEFAULT 50
        CHECK (reorder_qty > 0),

    PRIMARY KEY (warehouse_id, product_id)
);

CREATE TABLE stock_movement (
    movement_id BIGSERIAL PRIMARY KEY,

    warehouse_id INT NOT NULL,
    product_id INT NOT NULL,

    movement_type VARCHAR(5) NOT NULL
        CHECK (movement_type IN ('IN', 'OUT')),

    qty INT NOT NULL CHECK (qty > 0),
    moved_at TIMESTAMP NOT NULL DEFAULT now(),
    ref_type VARCHAR(10),
    ref_id INT,

    FOREIGN KEY (warehouse_id, product_id)
        REFERENCES inventory(warehouse_id, product_id)
);

-- =========================================================
-- 4. PURCHASE REQUISITIONS
-- =========================================================

CREATE TABLE purchase_requisition (
    req_id SERIAL PRIMARY KEY,

    requested_by INT NOT NULL
        REFERENCES employee(emp_id),

    dept_id INT REFERENCES department(dept_id),

    status VARCHAR(10) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'APPROVED',
            'REJECTED',
            'CONVERTED'
        )),

    approved_by INT REFERENCES employee(emp_id),

    source VARCHAR(10) NOT NULL DEFAULT 'MANUAL'
        CHECK (source IN ('MANUAL', 'AUTO', 'AGENT')),

    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE requisition_item (
    req_id INT NOT NULL
        REFERENCES purchase_requisition(req_id) ON DELETE CASCADE,

    product_id INT NOT NULL
        REFERENCES product(product_id),

    qty INT NOT NULL CHECK (qty > 0),

    PRIMARY KEY (req_id, product_id)
);

-- =========================================================
-- 5. PURCHASE ORDERS AND ORDER ITEMS
-- =========================================================

CREATE TABLE purchase_order (
    po_id SERIAL PRIMARY KEY,

    req_id INT REFERENCES purchase_requisition(req_id),

    supplier_id INT NOT NULL
        REFERENCES supplier(supplier_id),

    warehouse_id INT NOT NULL
        REFERENCES warehouse(warehouse_id),

    created_by INT NOT NULL
        REFERENCES employee(emp_id),

    approved_by INT REFERENCES employee(emp_id),

    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_date DATE NOT NULL,
    delivered_date DATE,

    status VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN (
            'DRAFT',
            'APPROVED',
            'SENT',
            'PARTIAL',
            'RECEIVED',
            'CLOSED',
            'CANCELLED'
        )),

    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    CONSTRAINT chk_po_expected_date
        CHECK (expected_date >= order_date)
);

CREATE TABLE po_item (
    po_id INT NOT NULL
        REFERENCES purchase_order(po_id) ON DELETE CASCADE,

    line_no INT NOT NULL,

    product_id INT NOT NULL
        REFERENCES product(product_id),

    qty_ordered INT NOT NULL CHECK (qty_ordered > 0),

    qty_received INT NOT NULL DEFAULT 0
        CHECK (qty_received >= 0 AND qty_received <= qty_ordered),

    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),

    PRIMARY KEY (po_id, line_no)
);

-- =========================================================
-- 6. GOODS RECEIPTS
-- =========================================================

CREATE TABLE goods_receipt (
    grn_id SERIAL PRIMARY KEY,

    po_id INT NOT NULL
        REFERENCES purchase_order(po_id),

    warehouse_id INT NOT NULL
        REFERENCES warehouse(warehouse_id),

    received_by INT NOT NULL
        REFERENCES employee(emp_id),

    received_date DATE NOT NULL DEFAULT CURRENT_DATE,

    -- Required to ensure each receipt belongs to its own PO.
    CONSTRAINT uq_goods_receipt_grn_po
        UNIQUE (grn_id, po_id)
);

CREATE TABLE grn_item (
    grn_id INT NOT NULL,
    line_no INT NOT NULL,

    po_id INT NOT NULL,
    po_line_no INT NOT NULL,

    qty_received INT NOT NULL DEFAULT 0
        CHECK (qty_received >= 0),

    qty_rejected INT NOT NULL DEFAULT 0
        CHECK (qty_rejected >= 0),

    PRIMARY KEY (grn_id, line_no),

    -- The receipt and PO must match.
    CONSTRAINT fk_grn_item_receipt_po
        FOREIGN KEY (grn_id, po_id)
        REFERENCES goods_receipt(grn_id, po_id)
        ON DELETE CASCADE,

    -- The referenced order line must belong to the specified PO.
    CONSTRAINT fk_grn_item_po_line
        FOREIGN KEY (po_id, po_line_no)
        REFERENCES po_item(po_id, line_no),

    -- A receipt line must record at least some received or rejected
    -- quantity. Rejected-only receipt lines are permitted.
    CONSTRAINT chk_grn_item_positive_quantity
        CHECK (qty_received + qty_rejected > 0)
);

-- =========================================================
-- 7. INVOICES AND PAYMENTS
-- =========================================================

CREATE TABLE invoice (
    invoice_id SERIAL PRIMARY KEY,

    po_id INT NOT NULL
        REFERENCES purchase_order(po_id),

    supplier_id INT NOT NULL
        REFERENCES supplier(supplier_id),

    invoice_no VARCHAR(30) NOT NULL,
    invoice_date DATE NOT NULL,
    due_date DATE NOT NULL,

    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),

    status VARCHAR(10) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN (
            'PENDING',
            'MATCHED',
            'DISPUTED',
            'PAID'
        )),

    UNIQUE (supplier_id, invoice_no),

    CONSTRAINT chk_invoice_due_date
        CHECK (due_date >= invoice_date)
);

CREATE TABLE payment (
    payment_id SERIAL PRIMARY KEY,

    invoice_id INT NOT NULL
        REFERENCES invoice(invoice_id),

    paid_on DATE NOT NULL DEFAULT CURRENT_DATE,

    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),

    method VARCHAR(15) NOT NULL
        CHECK (method IN ('NEFT', 'UPI', 'CHEQUE', 'CARD'))
);

-- =========================================================
-- 8. SUPPLIER EVALUATION
-- =========================================================

CREATE TABLE supplier_evaluation (
    eval_id SERIAL PRIMARY KEY,

    supplier_id INT NOT NULL
        REFERENCES supplier(supplier_id),

    po_id INT NOT NULL
        REFERENCES purchase_order(po_id),

    on_time BOOLEAN NOT NULL,

    days_late INT NOT NULL DEFAULT 0
        CHECK (days_late >= 0),

    quality_score NUMERIC(3,2)
        CHECK (quality_score BETWEEN 0 AND 5),

    evaluated_on DATE NOT NULL DEFAULT CURRENT_DATE,

    UNIQUE (po_id)
);

-- =========================================================
-- 9. AUDIT LOG
-- =========================================================

CREATE TABLE audit_log (
    log_id BIGSERIAL PRIMARY KEY,

    table_name VARCHAR(40) NOT NULL,
    record_id TEXT NOT NULL,

    action VARCHAR(10) NOT NULL,

    old_data JSONB,
    new_data JSONB,

    changed_by TEXT DEFAULT current_user,
    changed_at TIMESTAMP NOT NULL DEFAULT now()
);

-- =========================================================
-- 10. PREDICTIONS AND AGENT ACTIVITY
-- =========================================================

CREATE TABLE prediction (
    pred_id SERIAL PRIMARY KEY,

    po_id INT NOT NULL
        REFERENCES purchase_order(po_id),

    model_name VARCHAR(40) NOT NULL,

    late_prob NUMERIC(5,4) NOT NULL
        CHECK (late_prob BETWEEN 0 AND 1),

    predicted_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE agent_run (
    run_id SERIAL PRIMARY KEY,

    triggered_by TEXT NOT NULL,
    goal TEXT NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'RUNNING'
        CHECK (status IN (
            'RUNNING',
            'AWAITING_APPROVAL',
            'APPROVED',
            'REJECTED',
            'FAILED'
        )),

    draft_po_id INT REFERENCES purchase_order(po_id),
    justification TEXT,

    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE agent_tool_call (
    call_id BIGSERIAL PRIMARY KEY,

    run_id INT NOT NULL
        REFERENCES agent_run(run_id) ON DELETE CASCADE,

    tool VARCHAR(40) NOT NULL,
    args JSONB,
    result JSONB,

    called_at TIMESTAMP NOT NULL DEFAULT now()
);

-- =========================================================
-- 11. DOCUMENT EMBEDDINGS
-- =========================================================

CREATE TABLE document_chunk (
    chunk_id SERIAL PRIMARY KEY,

    supplier_id INT REFERENCES supplier(supplier_id),

    doc_name VARCHAR(100) NOT NULL,
    chunk_text TEXT NOT NULL,

    embedding vector(384)
);

-- =========================================================
-- 12. INDEXES FOR FOREIGN KEYS AND COMMON LOOKUPS
-- PostgreSQL does not automatically index FK columns.
-- =========================================================

CREATE INDEX idx_employee_dept
    ON employee(dept_id);

CREATE INDEX idx_supplier_contact_supplier
    ON supplier_contact(supplier_id);

CREATE INDEX idx_category_parent
    ON category(parent_id);

CREATE INDEX idx_product_category
    ON product(category_id);

CREATE INDEX idx_supplier_product_product
    ON supplier_product(product_id);

CREATE INDEX idx_stock_movement_inventory
    ON stock_movement(warehouse_id, product_id);

CREATE INDEX idx_stock_movement_moved_at
    ON stock_movement(moved_at);

CREATE INDEX idx_purchase_requisition_requested_by
    ON purchase_requisition(requested_by);

CREATE INDEX idx_purchase_requisition_dept
    ON purchase_requisition(dept_id);

CREATE INDEX idx_purchase_requisition_approved_by
    ON purchase_requisition(approved_by);

CREATE INDEX idx_requisition_item_product
    ON requisition_item(product_id);

CREATE INDEX idx_purchase_order_req
    ON purchase_order(req_id);

CREATE INDEX idx_purchase_order_supplier
    ON purchase_order(supplier_id);

CREATE INDEX idx_purchase_order_warehouse
    ON purchase_order(warehouse_id);

CREATE INDEX idx_purchase_order_created_by
    ON purchase_order(created_by);

CREATE INDEX idx_purchase_order_approved_by
    ON purchase_order(approved_by);

CREATE INDEX idx_purchase_order_status
    ON purchase_order(status);

CREATE INDEX idx_po_item_product
    ON po_item(product_id);

CREATE INDEX idx_goods_receipt_po
    ON goods_receipt(po_id);

CREATE INDEX idx_goods_receipt_warehouse
    ON goods_receipt(warehouse_id);

CREATE INDEX idx_goods_receipt_received_by
    ON goods_receipt(received_by);

CREATE INDEX idx_grn_item_po_line
    ON grn_item(po_id, po_line_no);

CREATE INDEX idx_invoice_po
    ON invoice(po_id);

CREATE INDEX idx_invoice_supplier
    ON invoice(supplier_id);

CREATE INDEX idx_invoice_status_due_date
    ON invoice(status, due_date);

CREATE INDEX idx_payment_invoice
    ON payment(invoice_id);

CREATE INDEX idx_supplier_evaluation_supplier
    ON supplier_evaluation(supplier_id);

CREATE INDEX idx_prediction_po_time
    ON prediction(po_id, predicted_at DESC);

CREATE INDEX idx_agent_run_status
    ON agent_run(status);

CREATE INDEX idx_agent_run_draft_po
    ON agent_run(draft_po_id);

CREATE INDEX idx_agent_tool_call_run
    ON agent_tool_call(run_id);

CREATE INDEX idx_document_chunk_supplier
    ON document_chunk(supplier_id);