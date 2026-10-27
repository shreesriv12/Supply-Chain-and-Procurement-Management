# Supply Chain & Procurement Management

Database-first procure-to-pay system for the E10 SchemaSquad DBMS project. The repository contains a PostgreSQL schema, indexes, reporting views, triggers/procedures, role grants, sample data, FastAPI endpoints, a React/Vite interface, ML pipelines and optional GenAI modules. Source presence is not runtime proof; use the validation commands below and record actual output.

## 1. Configure environment (Windows PowerShell)

Run from the repository root. Compose reads `.env` in this directory. Keep this file private and never commit live credentials.

**Fresh database (no existing PostgreSQL volume):**

```powershell
$pgPassword = python -c "import secrets; print(secrets.token_hex(32))"
$jwtSecret = python -c "import secrets; print(secrets.token_hex(32))"
@("POSTGRES_DB=scm", "POSTGRES_USER=scm_admin", "POSTGRES_PASSWORD=$pgPassword", "JWT_SECRET=$jwtSecret", "GROQ_API_KEY=") | Set-Content -Encoding ascii .env
```

**Existing database created with the previous compose file:** its database password is likely still `scm_admin`. Add `POSTGRES_PASSWORD=scm_admin` to the root `.env` first so the existing DB/API can reconnect, then follow the password-rotation steps in `docs/final_validation.md`. Merely changing the Compose environment does not change a password already stored in an initialized PostgreSQL volume.

## 2. Start the project

```powershell
docker compose config
docker compose up -d --build
docker compose ps
Invoke-RestMethod http://localhost:8000/health
```

API: `http://localhost:8000` (interactive docs at `/docs`). Web UI: `http://localhost:5173`.

Docker executes numbered `.sql` files directly in `db/` when the PostgreSQL data directory is initialized for the first time. Files in `db/demo/` are demonstrations and do not run as initialization scripts.

## 3. Database migration (important)

The forward migration is `db/10_fixes.sql`. On a fresh database initialization, it runs after `db/07_seed.sql`. For an already initialized database, Docker will not automatically replay it. Apply it without deleting the database volume:

```powershell
Get-Content db\10_fixes.sql -Raw | docker compose exec -T db psql -U scm_admin -d scm -v ON_ERROR_STOP=1
```

Do **not** run `docker compose down -v` for ordinary schema changes; that command deletes the local database volume and its data. Back up data and get explicit approval before any destructive reset.

## 4. Check views and seeded data

```powershell
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT COUNT(*) AS purchase_orders FROM purchase_order;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT COUNT(*) AS stock_movements FROM stock_movement;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT * FROM v_low_stock LIMIT 10;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT * FROM v_supplier_performance LIMIT 5;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT * FROM v_po_summary LIMIT 5;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT * FROM v_pending_payments LIMIT 5;"
docker compose exec -T db psql -U scm_admin -d scm -c "SELECT * FROM v_spend_by_category LIMIT 5;"
```

Treat counts shown by your own database as the real results. The generation script can prepare seed SQL, but do not regenerate `db/07_seed.sql` unless you intend to use it for a future clean initialization.

## 5. SQL demonstration files

Run the reporting query set with:

```powershell
docker compose exec -T db psql -U scm_admin -d scm -f /docker-entrypoint-initdb.d/demo/08_queries.sql
```

`db/demo/09_transactions_demo.sql` contains commented two-session examples. Follow its instructions in separate terminal sessions; comments alone do not demonstrate that a transaction test was executed.

## 6. API and authentication

For development, the seed generator creates users named `employee<N>@schemasquad.test` with the demo password `demo-password`. Newly generated seeds use salted PBKDF2-SHA256 hashes. The login code supports legacy SHA-256 seed hashes and upgrades them after successful login. Change demo credentials before any deployment; the synthetic credentials are not production identities.

The SQL utility returns the query text, parameter values, duration, affected-row count and result for ordinary API queries. Use the UI SQL panel to capture a real request and its actual result. Some AI/RAG response paths still need separate runtime verification before their SQL-panel metadata can be treated as real execution evidence.

## 7. Python tests

```powershell
$env:JWT_SECRET = "test-only-secret-for-unit-tests"
python -m pip install -r backend\requirements.txt
$env:PYTHONPATH = "$PWD\backend"
python -m pytest -q backend\tests
```

For ML and SQL-guardrail checks with a running stack:

```powershell
docker compose exec api python -m app.ml.train_late
docker compose exec api python -m app.ml.train_forecast
docker compose exec api python -m pytest backend/tests/test_nl2sql.py
```

Report only actual output and metrics.

## 8. Standalone frontend build

```powershell
Push-Location frontend
npm install
npm run build
Pop-Location
```

Set `VITE_API_URL` if the browser must reach an API at a different origin. The default is `http://localhost:8000/api`.

## 9. AI / ML

The ML scripts write model artifacts and JSON metrics under `backend/app/ml/models/` when training succeeds. Capture actual metrics after running the scripts; do not copy sample or estimated scores into the academic report. GenAI features require a valid `GROQ_API_KEY`; their behavior must be tested separately from core procurement workflows.

## 10. Documentation

- [Normalization and keys](docs/normalization.md)
- [ER/EER model description](docs/er_description.md)
- [Report outline](docs/report_outline.md)
- [Demo script](docs/demo_script.md)
- [Implementation gap audit](docs/implementation_gap_audit.md)
- [Final validation runbook](docs/final_validation.md)
