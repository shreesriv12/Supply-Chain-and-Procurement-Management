from __future__ import annotations

import hashlib
import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .db import run_sql

SECRET = os.getenv("JWT_SECRET", "development-only-secret")
ALGORITHM = "HS256"
bearer = HTTPBearer(auto_error=False)

def login(email: str, password: str) -> dict:
    result = run_sql("SELECT emp_id, name, email, password_hash, role FROM employee WHERE email = %s", [email])
    if not result["data"] or not _constant_time_equal(result["data"][0]["password_hash"], password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    employee = result["data"][0]
    token = jwt.encode({"sub": str(employee["emp_id"]), "role": employee["role"], "exp": datetime.now(timezone.utc) + timedelta(hours=8)}, SECRET, algorithm=ALGORITHM)
    return {"access_token": token, "token_type": "bearer", "employee": {key: employee[key] for key in ("emp_id", "name", "email", "role")}}

def _constant_time_equal(stored_hash: str, password: str) -> bool:
    return stored_hash == hashlib.sha256(password.encode()).hexdigest()

def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bearer token required")
    try:
        payload = jwt.decode(credentials.credentials, SECRET, algorithms=[ALGORITHM])
        return {"emp_id": int(payload["sub"]), "role": payload["role"]}
    except (jwt.InvalidTokenError, KeyError, ValueError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
