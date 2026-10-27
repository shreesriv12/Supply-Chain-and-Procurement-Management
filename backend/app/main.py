from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .auth import login
from .db import close_pool, open_pool
from .schemas import LoginRequest
from .routers import suppliers, products, inventory, requisitions, orders, receipts, invoices, reports, schema, ml, ai

@asynccontextmanager
async def lifespan(_: FastAPI):
    open_pool()
    yield
    close_pool()

app = FastAPI(title="SchemaSquad SCM API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["http://localhost:5173"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

@app.get("/health")
def health(): return {"status": "ok"}
@app.post("/auth/login")
def sign_in(body: LoginRequest): return login(body.email, body.password)

for router in (suppliers.router, products.router, inventory.router, requisitions.router, orders.router, receipts.router, invoices.router, reports.router, schema.router, ml.router, ai.router):
    app.include_router(router, prefix="/api")
