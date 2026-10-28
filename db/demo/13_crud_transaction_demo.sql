-- Safe DML demonstration: INSERT, UPDATE, SELECT and DELETE are all rolled back.
-- Run against the demo database. The inserted supplier ID comes from the sequence.
\set ON_ERROR_STOP on
\echo '=== Begin a transaction for reversible CRUD demonstration ==='
BEGIN;

INSERT INTO supplier (name, country, status, rating)
VALUES ('DBMS-DEMO-' || txid_current()::text, 'India', 'ACTIVE', 4.0)
RETURNING supplier_id \gset

UPDATE supplier
SET city = 'Demo City'
WHERE supplier_id = :supplier_id
RETURNING supplier_id, name, city, status;

SELECT supplier_id, name, city, status
FROM supplier
WHERE supplier_id = :supplier_id;

DELETE FROM supplier
WHERE supplier_id = :supplier_id
RETURNING supplier_id, name;

ROLLBACK;
\echo '=== The transaction was rolled back; the demo supplier row should not persist ==='
SELECT COUNT(*) AS demo_rows_remaining
FROM supplier
WHERE supplier_id = :supplier_id;

-- Do not remove the ROLLBACK: this script is intentionally non-persistent.
