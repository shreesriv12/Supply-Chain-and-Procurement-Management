# Project Report Outline

## 1. Abstract

State that the project delivers a PostgreSQL-centered procure-to-pay system covering requisition, approval, PO, receipt, invoice matching, payment, supplier performance, forecasting, and guarded GenAI access.

## 2. Problem statement and objectives

Explain fragmented procurement records, poor stock visibility, invoice mismatch risk, and supplier uncertainty. List objectives: normalized central data, database-enforced rules, role-based access, transparent SQL UI, predictive delivery/forecast features, and approval-safe AI.

## 3. Requirements and architecture

Include functional/non-functional requirements, architecture diagram, Docker services, and why raw SQL is surfaced in the UI.

## 4. Data design

Include the ER diagram, entity descriptions, keys, FKs, and the full normalization walkthrough from `normalization.md`.

## 5. Database implementation

Describe schema, indexes, five views, triggers, procedures, role grants, and the 3,000-PO / 20,000-movement deterministic seed set. Include selected `EXPLAIN ANALYZE` evidence before and after indexing.

## 6. Transaction management and security

Show the atomic receipt rollback, check-constraint rejection, `FOR UPDATE` fix for concurrent stock issue, isolation-level demonstration, deadlock pattern/fix, and application roles.

## 7. Application implementation

Cover FastAPI, raw SQL response metadata, JWT role mapping, React pages, SQL panel, and schema browser. Add screenshots from the running UI.

## 8. ML implementation and results

Describe the chronological split, leakage prevention, features, model comparison, classifier metrics, demand baseline versus model MAE/MAPE, and UI integration. Insert generated metrics after training.

## 9. GenAI implementation and safety

Document Groq via the OpenAI-compatible client, whitelisted text-to-SQL validation, `nl_readonly`, forced limits/timeouts, prompt-injection tests, tool logging, draft-only agent writes, `LISTEN/NOTIFY` worker, and pgvector RAG.

## 10. Testing, limitations, and future work

Include automated guardrail tests and manual database scenario tests. Note that production needs secrets management, managed Postgres, migrations, authentication hardening, observability, and model monitoring.

## 11. Conclusion

Summarize how database rules remain authoritative even when the UI and AI layers are present.
