# Project Report Outline — DBMS Project Work

Use the exact order below when preparing the final report. The official project-plan and submission-notice PDFs must be checked by the team before submission; they were not attached to this audit session. Do not insert invented student details, runtime outputs, screenshots, or model metrics.

## 1. Title Page
Use the institution/template supplied by the course. Project: **Supply Chain & Procurement Management System**; Team: **E10 SchemaSquad**; Institution: **Motilal Nehru National Institute of Technology Allahabad, Prayagraj**; Course: **DBMS Project Work**; Academic year: **2026–2027**. Copy student names and registration numbers exactly from the supplied team materials.

## 2. Abstract
Summarize the verified procurement workflow, PostgreSQL data model, SQL business rules, UI/backend, and only those ML/AI features demonstrated in a real run.

## 3. Introduction and Problem Statement
Explain fragmented procurement data, inventory visibility, approval traceability, receipt discrepancies, invoice/payment matching, and supplier evaluation.

## 4. Project Objectives and Scope
List core procure-to-pay goals, database constraints, reports, role-based access, SQL transparency and the ML task. Separate implemented scope from future scope.

## 5. System Analysis and Requirements
Include functional and non-functional requirements, user roles, data flow, assumptions, scope boundaries, dependencies and acceptance criteria.

## 6. ER/EER Diagram and Database Schema
Insert `docs/er_diagram.svg` or a regenerated editable equivalent, describe entities/relationships/cardinalities, then show relation schemas with PK/FK labels. Explain associative entities such as `supplier_product`, `inventory`, `requisition_item` and `po_item`.

## 7. Keys, Functional Dependencies and Normalization
Use `docs/normalization.md`. Include candidate-key and FK tables, the `PO_SHEET` FDs, 1NF → 2NF → 3NF decomposition, BCNF discussion, and clearly separate hypothetical dependencies from actual constraints.

## 8. SQL Implementation (DDL, DML, Joins, Subqueries, etc.)
Show selected real SQL from `db/01_schema.sql` and `db/demo/08_queries.sql`: DDL, CRUD DML, joins, grouping/HAVING, nested/correlated queries, EXISTS/NOT EXISTS, CTEs, window functions and date/spend queries. Provide actual output snippets.

## 9. Views, Indexes, Triggers and Transactions Implemented
Describe all five views, representative indexes, business-rule triggers, procedures and role grants. Include `EXPLAIN ANALYZE` outputs and transaction/concurrency observations only after running them.

## 10. Front-End Design and Database Connectivity
Show React/FastAPI/PostgreSQL architecture. Explain parameterized raw SQL, transaction boundaries, JWT claims, database-role mapping, CORS, loading/error handling and the SQL panel's actual execution metadata. Add genuine screenshots.

## 11. CRUD Operations and Report Generation
Demonstrate insert/search/update/delete where safe, workflow actions for historical/financial entities, reporting filters, and export only if it was actually verified.

## 12. AI/ML Implementation and Model Evaluation
Document dataset source and counts, target definition, temporal split, leakage prevention, preprocessing, baseline and compared model, accuracy/precision/recall/F1/ROC-AUC/confusion matrix where applicable, and actual saved metrics. For forecasting, report the naive baseline and actual MAE/MAPE only after training. Include prediction API/UI evidence.

## 13. Testing, Results and Screenshots
Use a test table with command, scenario, expected result, actual result, pass/fail and evidence filename. Include DB integrity, role denial, receipt boundary, invoice/payment, rollback/concurrency, API tests, frontend build and end-to-end workflow. Mark environment-blocked tests as pending.

## 14. Conclusion and Future Scope
Summarize verified outcomes and limitations. Future work may include deployment hardening, richer forecasts, document ingestion formats and model monitoring, but do not present these as completed features.

## 15. References/Bibliography
Cite PostgreSQL, FastAPI, React/Vite, scikit-learn and any external dataset or policy material actually used. Record dataset versions/licences and access dates. Do not add references that were not consulted.

## Evidence still needed after a real run

- [ ] Official title-page/template and exact team registration details.
- [ ] Actual database table counts and five-view outputs.
- [ ] Output for successful and rejected workflow scenarios.
- [ ] Trigger/procedure and role-denial evidence.
- [ ] Transaction/concurrency results from separate sessions.
- [ ] Frontend screenshots showing real SQL and returned data.
- [ ] ML metric JSON, confusion matrix/plots, prediction response and UI screenshot.
- [ ] Actual test summary and frontend build output.
