# Viva Demonstration Script

## Preparation

1. Set `GROQ_API_KEY` in a local environment file or shell.
2. Run `python backend/seed/generate_seed.py`.
3. Start the stack: `docker compose up --build`.
4. Train both models from the API container.
5. Sign in at `http://localhost:5173` with `employee1@schemasquad.test` and `demo-password`.

## Eight-minute flow

1. **Architecture (30 seconds):** show Docker services and explain that PostgreSQL owns business rules while the UI shows the SQL generated for each operation.
2. **Data model (60 seconds):** open Schema & ER. Explain the supplier-product and warehouse-product many-to-many relations, then show the live table/column browser.
3. **Inventory rule (60 seconds):** open Inventory and Low Stock. Explain the non-negative CHECK, low-stock trigger, auto requisition, and notification.
4. **Procurement flow (90 seconds):** show a requisition, approval, created PO, and the PO lines. Explain the approved-requisition and approval-limit rules.
5. **Receipt and invoice (90 seconds):** receive against a PO. Show that the GRN trigger updates `po_item`, inventory, stock movement, and PO status. Show matched versus disputed invoices and explain the 2% three-way-match tolerance.
6. **SQL panel (30 seconds):** perform any refresh/action and point out parameterized SQL, parameter values, duration, rows affected, and raw result.
7. **ML (60 seconds):** open ML insights, predict a PO's late-delivery risk, then show reorder recommendations. Explain time split and no leakage.
8. **GenAI safety (90 seconds):** ask a reporting question in Ask Data, edit the displayed SQL, and explain why destructive SQL is rejected. Run Procurement Agent, show `AWAITING_APPROVAL`, the draft PO ID, and the tool log. Optionally upload a text policy and ask a cited question.

## Suggested viva questions

**Why are constraints/triggers preferable to application-only validation?** Every client, including scripts, API, and AI agent, must obey the same rules at the database boundary.

**How is the lost-update problem handled?** The transaction demo contrasts unprotected read-modify-write with `SELECT ... FOR UPDATE`, which serializes access to the inventory row.

**How does text-to-SQL avoid destructive access?** The model output is parsed with sqlglot, must be a single SELECT against named reporting views, receives a forced limit and timeout, and executes through the `nl_readonly` role.

**Why are agent writes drafts only?** The agent can recommend and create a DRAFT PO, but cannot approve/send it. A human manager completes the irreversible business action.
