# Supply Chain & Procurement Management

Database-first procure-to-pay system for the E10 SchemaSquad DBMS project. The completed database foundation includes schema, indexes, reporting views, business-rule triggers, procedures, RBAC, query demonstrations, and a deterministic seed generator.

## Start the database

1. Generate the seed file: `python backend/seed/generate_seed.py`
2. Start the database and API: `docker compose up -d --build`
3. Inspect reporting data: `docker compose exec db psql -U scm_admin -d scm -c "SELECT * FROM v_low_stock;"`

Docker runs numbered files in `db/` only when its database volume is first created. To reseed during development, run `docker compose down -v`, generate the seed again, then start the service.

## Phase 1 validation

```sql
SELECT COUNT(*) FROM purchase_order;       -- 3000
SELECT COUNT(*) FROM stock_movement;       -- 20000
SELECT * FROM v_low_stock;
SELECT * FROM v_supplier_performance LIMIT 5;
```

The next phase adds database-enforced triggers, procedures, RBAC, query demonstrations, and transaction/concurrency exercises.

## Database logic and demos

`04_functions_triggers.sql` enforces blocked-supplier, requisition, receipt-tolerance, invoice-match, delivery-scorecard, price-audit, and low-stock rules. `05_procedures.sql` provides the approved workflow entry points. `06_roles.sql` grants least privilege to the application roles; create actual LOGIN users separately and grant them the appropriate application role.

Run the query set with `docker compose exec db psql -U scm_admin -d scm -f /docker-entrypoint-initdb.d/08_queries.sql`. Use the commented two-session blocks in `09_transactions_demo.sql` for the ACID and concurrency viva demos.

## API

The FastAPI service is served at `http://localhost:8000`; interactive endpoint documentation is at `/docs`. Every data endpoint returns `data`, `executed_sql`, `params`, `duration_ms`, and `rows_affected` for the global SQL panel.

For development, log in with any generated `employee<N>@schemasquad.test` email and password `demo-password`, then supply the returned bearer token. Change `JWT_SECRET`, replace the development password seed, and provision LOGIN users before deployment.

## Web app

The React application is served at `http://localhost:5173` by Docker. For standalone frontend work, use `cd frontend`, `npm install`, then `npm run dev`. It provides the dashboard, supplier/product/inventory/requisition/order/receipt/invoice/report pages, global SQL query panel, and live schema browser. The browser connects to `http://localhost:8000` by default; set `VITE_API_URL` when deploying it elsewhere.

## ML training

After the database is seeded, train the models from the API container:

`docker compose exec api python -m app.ml.train_late`

`docker compose exec api python -m app.ml.train_forecast`

Each script uses a time-based split and writes a `joblib` model plus JSON metrics under `backend/app/ml/models/`. The **ML insights** page then exposes late-risk predictions and forecast-driven reorder suggestions.

### Synthetic and real-data evaluation

The live database stays on the deterministic synthetic seed because it has a complete, internally consistent procure-to-pay lifecycle. Real data is used as a separate, reproducible ML evaluation source:

- **DataCo Supply Chain**: real late-delivery-risk classification.
- **M5 Forecasting Accuracy**: retail demand forecasting.
- **Olist**: external order, product, seller, payment, and delivery data available for analysis; it is not forced into the internal procurement workflow because it has a different marketplace data model.

Profile the locally added files with `python backend/seed/inspect_real_datasets.py`. Train external models with `python -m app.ml.train_real_data --dataset all` from `backend/`; reduce M5 runtime with `--m5-series 100` or DataCo runtime with `--dataco-rows 20000`. Metrics and model artifacts are saved beside the existing synthetic-data models.

## Groq GenAI

Set `GROQ_API_KEY` in your shell or a local `.env` file (which is ignored by Git), then start the stack with `docker compose up --build`. The API uses the OpenAI Python client configured for Groq's compatible endpoint and model `openai/gpt-oss-20b` by default. Override it with `GROQ_MODEL` if needed.

The **Ask Data** page generates and validates one `SELECT` query against reporting views only, then executes it as `nl_readonly` with a timeout and a forced row limit. The **Procurement agent** logs tool calls and can create only `DRAFT` POs for manager approval. The worker listens for `low_stock` notifications and follows the same approval-only path. **Policy Q&A** indexes plain-text policy documents into pgvector and answers from retrieved chunks. It uses a lightweight built-in embedding fallback by default; optionally install `sentence-transformers` for MiniLM semantic embeddings.

Run the guardrail tests with `docker compose exec api pytest backend/tests/test_nl2sql.py`.

## Documentation and viva

- [Normalization and keys](docs/normalization.md)
- [ER/EER model description](docs/er_description.md)
- [Report outline](docs/report_outline.md)
- [Eight-minute demonstration script](docs/demo_script.md)

For a clean first run after changing database initialization files, use `docker compose down -v`, regenerate `db/07_seed.sql`, then start the stack again. This removes the local Docker database volume only; do not run it if you need to preserve local records.
