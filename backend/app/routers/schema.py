from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from ..auth import current_user
from ..db import run_sql

router = APIRouter(prefix="/schema", tags=["schema"])

@router.get("/er-diagram", include_in_schema=False)
def er_diagram():
    diagram = Path(__file__).resolve().parents[3] / "docs" / "er_diagram.svg"
    return FileResponse(diagram, media_type="image/svg+xml", filename="er_diagram.svg")

@router.get("/tables")
def tables(user: dict = Depends(current_user)):
    return run_sql("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name", app_role=user["role"])

@router.get("/tables/{table_name}/columns")
def columns(table_name: str, user: dict = Depends(current_user)):
    if not table_name.replace("_", "").isalnum():
        raise HTTPException(400, "Invalid table name")
    return run_sql("SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position", [table_name], app_role=user["role"])
