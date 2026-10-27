from __future__ import annotations
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from ..ai.agent import run_reorder_agent
from ..ai.nl2sql import question_to_sql, validate_sql
from ..ai.rag import answer, index_text
from ..auth import current_user
from ..db import run_sql

router = APIRouter(prefix="/ai", tags=["GenAI"])
class Question(BaseModel): question: str
class SqlRequest(BaseModel): sql: str
class AgentRequest(BaseModel): product_id: int; warehouse_id: int; quantity: int | None = Field(default=None, gt=0)
@router.post("/ask-data")
def ask_data(body: Question, user: dict = Depends(current_user)):
    try: query = question_to_sql(body.question)
    except (ValueError, RuntimeError) as exc: raise HTTPException(400, str(exc)) from exc
    return run_sql(query, app_role="nl_readonly")
@router.post("/ask-data/execute")
def execute_edited_sql(body: SqlRequest, user: dict = Depends(current_user)):
    try: query = validate_sql(body.sql)
    except ValueError as exc: raise HTTPException(400, str(exc)) from exc
    return run_sql(query, app_role="nl_readonly")
@router.post("/agent/reorder")
def agent_reorder(body: AgentRequest, user: dict = Depends(current_user)):
    try: return run_reorder_agent(body.product_id, body.warehouse_id, user["emp_id"], body.quantity)
    except (ValueError, RuntimeError) as exc: raise HTTPException(400, str(exc)) from exc
@router.get("/agent/runs")
def agent_runs(user: dict = Depends(current_user)):
    return run_sql("SELECT * FROM agent_run ORDER BY created_at DESC", app_role=user["role"])
@router.post("/rag/upload")
async def upload_contract(file: UploadFile = File(...), supplier_id: int | None = Form(default=None), user: dict = Depends(current_user)):
    if not file.filename.lower().endswith(".txt"): raise HTTPException(400, "Upload plain-text policy/contract files in this build")
    text = (await file.read()).decode("utf-8", errors="replace")
    count = index_text(file.filename, text, supplier_id)
    return {"data": [{"doc_name": file.filename, "chunks_indexed": count}], "executed_sql": ["INSERT INTO document_chunk (...)"], "params": [[]], "duration_ms": 0, "rows_affected": count}
@router.post("/rag/ask")
def ask_policy(body: Question, user: dict = Depends(current_user)):
    try: result = answer(body.question)
    except RuntimeError as exc: raise HTTPException(400, str(exc)) from exc
    return {"data": [result], "executed_sql": ["SELECT ... FROM document_chunk ORDER BY embedding <=> query_embedding LIMIT 4"], "params": [[]], "duration_ms": 0, "rows_affected": len(result["sources"])}
