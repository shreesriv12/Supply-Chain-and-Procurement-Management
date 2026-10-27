"""Focused password-hashing regression tests; no database connection is required."""
import hashlib
from app.security import hash_password, verify_password


def test_pbkdf2_hash_verifies_and_is_salted():
    first = hash_password("demo-password")
    second = hash_password("demo-password")
    assert first != second
    assert verify_password(first, "demo-password") == (True, False)
    assert verify_password(first, "wrong-password")[0] is False


def test_legacy_seed_hash_is_verified_and_marked_for_upgrade():
    old_hash = hashlib.sha256(b"demo-password").hexdigest()
    assert verify_password(old_hash, "demo-password") == (True, True)
    assert verify_password(old_hash, "wrong-password")[0] is False
