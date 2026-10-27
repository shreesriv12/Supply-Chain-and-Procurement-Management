from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .db import ROLE_MAP, run_sql
from .security import hash_password, verify_password

SECRET = os.getenv("JWT_SECRET")
if not SECRET:
    raise RuntimeError(
        "JWT_SECRET is required. Set it in the project-root .env file before starting the API."
    )
ALGORITHM = "HS256"
bearer = HTTPBearer(auto_error=False)

EMPLOYEE_ROLES = {"admin", "procurement_mgr", "warehouse_staff", "finance", "viewer"}


def login(email: str, password: str) -> dict:
    result = run_sql(
        "SELECT emp_id, name, email, password_hash, role FROM employee WHERE email = %s",
        [email],
    )
    if not result["data"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    employee = result["data"][0]
    valid, needs_rehash = verify_password(employee["password_hash"], password)
    if not valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
    if employee["role"] not in EMPLOYEE_ROLES or employee["role"] not in ROLE_MAP:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Employee role is not permitted")

    # Upgrade old unsalted SHA-256 hashes after a successful login. The WHERE clause
    # avoids overwriting a concurrent password change.
    if needs_rehash:
        run_sql(
            "UPDATE employee SET password_hash = %s WHERE emp_id = %s AND password_hash = %s",
            [hash_password(password), employee["emp_id"], employee["password_hash"]],
            app_role="admin",
        )

    token = jwt.encode(
        {
            "sub": str(employee["emp_id"]),
            "role": employee["role"],
            "exp": datetime.now(timezone.utc) + timedelta(hours=8),
        },
        SECRET,
        algorithm=ALGORITHM,
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "employee": {
            key: employee[key] for key in ("emp_id", "name", "email", "role")
        },
    }


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer token required",
        )
    try:
        payload = jwt.decode(
            credentials.credentials,
            SECRET,
            algorithms=[ALGORITHM],
            options={"require": ["exp", "sub", "role"]},
        )
        role = payload["role"]
        emp_id = int(payload["sub"])
        if role not in EMPLOYEE_ROLES or role not in ROLE_MAP or emp_id <= 0:
            raise jwt.InvalidTokenError("Invalid employee claims")
        return {"emp_id": emp_id, "role": role}
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        ) from exc
