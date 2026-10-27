sql
-- Supply Chain and Procurement Management
-- Performance indexes
-- Assumes db/01_schema.sql has already been executed.

-- Purchase orders: supplier/date filtering
CREATE INDEX IF NOT EXISTS idx_po_supplier_date
    ON purchase_order(supplier_id, order_date);

-- Purchase orders: status filtering
-- idx_purchase_order_status is already created in 01_schema.sql.
-- Do not create another index on the same status column.

-- Purchase order items: product lookups
-- idx_po_item_product is already created in 01_schema.sql.

-- Invoices: status and due-date filtering
-- idx_invoice_status_due_date is already created in 01_schema.sql.

-- Stock movement history for a product
CREATE INDEX IF NOT EXISTS idx_movement_prod_time
    ON stock_movement(product_id, moved_at DESC);

-- Low-stock inventory lookup
CREATE INDEX IF NOT EXISTS idx_inventory_low_stock
    ON inventory(warehouse_id, product_id)
    WHERE qty_on_hand <= reorder_level;

-- Vector similarity search for document embeddings
CREATE INDEX IF NOT EXISTS idx_chunk_embedding
    ON document_chunk
    USING hnsw (embedding vector_cosine_ops);
