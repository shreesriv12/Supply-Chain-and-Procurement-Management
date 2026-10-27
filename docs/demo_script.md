# Viva Demonstration Script (8–10 minutes)

**Evidence rule:** capture outputs from the live environment. If a step fails, show the failure honestly and explain the blocker; do not use a mock screenshot as execution evidence.

## Before the demo

1. Confirm `.env` contains a non-committed `JWT_SECRET`; set `GROQ_API_KEY` only if showing GenAI.
2. Start with `docker compose up -d --build`, verify `docker compose ps` and `Invoke-RestMethod http://localhost:8000/health`.
3. Apply `db/10_fixes.sql` manually if the database volume existed before the migration file was added.
4. Run the ML training command if the model artifacts are missing and save actual metrics.
5. Sign in at `http://localhost:5173` with a seeded employee account. The generated seed currently uses `employee<N>@schemasquad.test` and demo password `demo-password`; replace demo identities before deployment.

## Live sequence

1. **Architecture (30 sec):** show the React frontend, FastAPI backend, PostgreSQL/pgvector and optional ML/GenAI modules. Emphasize that DB constraints—not only React—protect business rules.
2. **Schema and normalization (60 sec):** show the ER/schema browser. Explain composite keys on inventory, supplier-product and PO lines; distinguish the illustrative `PO_SHEET` key from actual `(po_id, line_no)`.
3. **Report and SQL panel (45 sec):** open low-stock or supplier-performance reporting. Point to the exact SQL, bound parameters, duration, affected rows and returned data for a real request.
4. **Requisition and approval (90 sec):** create a requisition with multiple items, show the transaction result, approve as a manager, then create and approve the PO. Explain approval limits and why direct unauthorized approval should be rejected.
5. **Receiving and inventory (90 sec):** receive goods against an approved/sent PO. Show the GRN line, inventory quantity, stock movement and PO status. Try one receipt over the documented 105% limit; capture the actual database rejection. Use a stable `ref_no` for a retry/idempotency example.
6. **Invoice/payment (60 sec):** show a matched invoice with an accepted receipt and a disputed invoice that fails matching. Demonstrate that an unmatched invoice and an overpayment are rejected.
7. **ML prediction (60 sec):** show the model name, probability/prediction response and saved metric JSON. Explain the time-based split and avoiding supplier-history leakage. State actual metrics only.
8. **AI safety (optional, 60–90 sec):** ask Ask Data for a reporting query. Show a rejected write statement and restricted role. Run the agent and verify it creates a draft that awaits manager approval; do not claim the agent sent/approved an order.
9. **Wrap-up (20 sec):** state verified strengths and any remaining limitations.

## Viva prompts

- Why must business rules live in PostgreSQL as well as in the UI?
- What is the difference between a primary key and a candidate key?
- Which functional dependencies cause partial/transitive dependencies in `PO_SHEET`?
- How does `SELECT ... FOR UPDATE` prevent competing stock issues from both consuming the same balance?
- Why do invoice matching and payment insertion need transactional checks and row locks?
- Why is a time-based split more appropriate than a random split for historical delivery predictions?
- Why is the AI agent limited to draft purchase orders?
