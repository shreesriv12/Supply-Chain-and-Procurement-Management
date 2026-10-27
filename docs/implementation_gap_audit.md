# Implementation Gap Audit — Supply Chain & Procurement Management

**Evidence boundary:** This audit was prepared from source-code inspection of the public repository. The project-plan PDF, submission-notice PDF and general-instructions screenshot were not available as files in this working session. No local PostgreSQL, Docker, browser or test execution was available, so this document does not label source inspection as runtime verification.

Status codes: **A** planned/documented only; **B** code present but integration/runtime unclear; **C** implementation supported by source inspection; **D** actually tested with recorded evidence; **E** missing or defective.

| Requirement | Source evidence | Status before fixes | Priority | Gap / acceptance test |
|---|---|---:|---:|---|
| Relational schema, PKs and FKs | `db/01_schema.sql` | C | P0 | Inspect every table and FK; run schema catalog checks on a fresh DB. |
| Reporting views | `db/03_views.sql` | E | P0 | File began with a stray `sql` token; `psql -v ON_ERROR_STOP=1` must apply the file without error and all five required views must exist. |
| Business-rule triggers and procedures | `db/04_functions_triggers.sql`, `db/05_procedures.sql`, `db/demo/10_fixes.sql` | B/E | P0 | Fix migration placement; verify blocked suppliers, approval limits, receipt tolerance, payment matching and payment cap through direct SQL and API attempts. |
| Forward migration path | `docker-compose.yml`, `db/demo/10_fixes.sql` | E | P0 | Docker only auto-processes root files in `/docker-entrypoint-initdb.d`; apply migration to an existing DB with the documented PowerShell pipeline and prove rerunning is safe. |
| Receipt tolerance | `db/01_schema.sql`, migration | E | P0 | Existing `qty_received <= qty_ordered` check contradicts the stated 105% tolerance. Drop that upper-bound check and enforce the ceiling at the receipt trigger; test accepted and rejected boundaries. |
| Authentication password storage | `backend/app/auth.py`, `backend/seed/generate_seed.py` | E | P0 | Existing code used plain SHA-256 digest comparison; use salted PBKDF2 and support one-time upgrade for legacy demo hashes. Test correct/wrong password and legacy upgrade. |
| JWT configuration and claims | `backend/app/auth.py`, `docker-compose.yml` | E/B | P0 | Remove hard-coded JWT secret fallback, require env configuration, require exp/sub/role claims and reject roles not held by employees. Test missing/expired/invalid tokens. |
| Requisition transaction | `backend/app/routers/requisitions.py` | E | P0 | Header and items were inserted in separate transactions. Use one data-modifying CTE and test a bad item leaves no header behind. |
| Inventory adjustment audit trail | `backend/app/routers/inventory.py`, `db/01_schema.sql` | E | P0 | The prior API changed `inventory.qty_on_hand` without recording a matching `stock_movement`. Make balance change and movement insertion one parameterized SQL statement; verify positive, negative, zero and overdrawn adjustments. |
| Receipt retry semantics | `backend/app/schemas.py`, `backend/app/routers/receipts.py`, migration | B | P1 | Pass an optional `ref_no` through to the unique `(po_id, ref_no)` index; test duplicate non-null references are rejected. Clients must send the same reference on retries. |
| Role-based SQL execution | `backend/app/db.py`, `backend/app/auth.py`, `db/06_roles.sql` | B | P0 | Source maps employee role to `SET LOCAL ROLE`; verify DB privileges with real LOGIN/role test identities. |
| SQL panel | `backend/app/db.py`, `frontend/src/components/SqlPanel.jsx` | B | P1 | Normal SQL calls return statement, parameter list, duration and row count. Verify a mutation end-to-end. RAG endpoints currently return placeholder SQL/zero duration and should not be presented as measured execution evidence until fixed. |
| ML classifier / forecast | `backend/app/ml/train_late.py`, `backend/app/ml/train_forecast.py`, `backend/app/routers/ml.py` | B | P0 | Training/inference code exists; no model training or metrics were run in this session. Train with seeded DB, inspect generated metrics and call prediction endpoint. |
| Late-classifier feature consistency | `backend/app/ml/train_late.py`, `backend/app/routers/ml.py` | E/B | P0 | Training grouped by PO and category (multiple rows can be emitted for one PO), while inference used one row and `MIN(category)`. Historical features could count incomplete deliveries and use current supplier rating. Use one row per PO, align category/aggregate features, and use only delivered orders/evaluations available before the PO order date; compare feature names and run training/inference. |
| Natural-language SQL guardrails | `backend/app/ai/nl2sql.py`, `backend/tests/test_nl2sql.py` | B | P1 | Validator parses one SELECT and whitelists views; tests exist but were not executed in this session. Add tests for CTEs, quoted identifiers, comments, multiple statements and timeout. |
| Frontend build / end-to-end workflow | `frontend/src`, `frontend/package.json`, `docker-compose.yml` | B | P0 | Code is present; install dependencies, build, start stack and test login → requisition → approval → PO → receipt → invoice/payment. |
| Academic report and assignment-template compliance | `docs/report_outline.md`, `docs/normalization.md` | B | P0 | A report outline and normalization note exist. Compare against the official PDFs and fill screenshots/results only after an actual run. |
| Runtime / CI acceptance evidence | `backend/tests`, repository workflow state not inspected | E/B | P0 | No local test run was possible; record commands and real results in `docs/final_validation.md`. |

## Change acceptance checklist

- [ ] Fresh-volume initialization reaches the end without SQL errors.
- [ ] Existing-volume migration runs without destroying data and can be re-run.
- [ ] A receipt at the permitted 105% boundary is accepted; one above it is rejected.
- [ ] Attempts to mutate a posted receipt or alter PO lines after approval are rejected.
- [ ] Payment without a valid three-way match and payment above invoice balance are rejected.
- [ ] Legacy demo password is upgraded after successful login; new seeds use PBKDF2-SHA256 with unique salt.
- [ ] Invalid roles/JWT claims are rejected.
- [ ] Requisition header and items roll back together on an invalid child row.
- [ ] The late-classifier training query yields one labelled row per PO; its columns match the online feature query and historical features stop at each PO order date.
- [ ] Inventory adjustments write an equal signed stock movement in the same transaction; an overdraw attempt changes neither table.
- [ ] Python tests, Docker health checks, API smoke tests and frontend build are run and their actual output is recorded.

## Bundle change map and verification boundary

The companion fix installer supplies or applies these changes: remove the stray `sql` token; promote and harden the forward migration at `db/10_fixes.sql`; make the 105% tolerance consistent with the table CHECK; guard PO approval and PO line edits at the database boundary; make posted receipt lines immutable; handle rejected-only receipts without a zero-quantity stock movement; pass receipt `ref_no` through the API; use one SQL statement for requisition header plus items; require env-sourced database/JWT secrets; migrate password checks to salted PBKDF2 with legacy-hash upgrade; align the late-classifier's training/inference features and prevent future-history leakage, regenerate the ER diagram from DOT, and correct runbook, normalization and report-outline documentation.

These source changes are **not runtime proof**. After applying the bundle, run the exact commands in `docs/final_validation.md`. Update this audit with actual test outputs and change statuses to D only for tests that demonstrably passed. If a migration fails because real data violates a new unique index, stop and investigate the duplicates; do not delete data to force success.
