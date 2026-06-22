"""Constant-time hashing helpers for opaque tokens.

We hash refresh tokens, API keys, and pair codes before storing them so a DB leak
doesn't expose live credentials.
"""
import hashlib
import hmac

from app.settings import get_settings


def _hmac_key() -> bytes:
    # Reuse the JWT secret as the HMAC pepper. Rotating the secret invalidates all
    # outstanding refresh tokens & API keys, which is the correct behaviour.
    return get_settings().jwt_secret.get_secret_value().encode()


def hash_token(token: str) -> str:
    return hmac.new(_hmac_key(), token.encode(), hashlib.sha256).hexdigest()


def verify_token(token: str, stored_hash: str) -> bool:
    return hmac.compare_digest(hash_token(token), stored_hash)
