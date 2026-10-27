"""Password-hashing utilities kept independent from database/API dependencies."""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets

PBKDF2_ITERATIONS = 600_000
_LEGACY_SHA256_RE = re.compile(r"^[0-9a-f]{64}$", re.IGNORECASE)


def hash_password(password: str) -> str:
    """Return a salted PBKDF2-SHA256 password hash suitable for storage."""
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS
    )
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(stored_hash: str, password: str) -> tuple[bool, bool]:
    """Return (matches, needs_rehash); safely supports legacy SHA-256 seed hashes."""
    if not isinstance(stored_hash, str):
        return False, False

    if _LEGACY_SHA256_RE.fullmatch(stored_hash):
        legacy = hashlib.sha256(password.encode("utf-8")).hexdigest()
        return hmac.compare_digest(stored_hash.lower(), legacy), True

    try:
        scheme, iterations_text, salt_hex, expected_hex = stored_hash.split("$", 3)
        iterations = int(iterations_text)
        if scheme != "pbkdf2_sha256" or not 100_000 <= iterations <= 2_000_000:
            return False, False
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(expected_hex)
        if len(salt) < 16 or len(expected) != 32:
            return False, False
    except (ValueError, TypeError):
        return False, False

    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected), iterations < PBKDF2_ITERATIONS
