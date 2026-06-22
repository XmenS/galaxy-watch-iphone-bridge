"""Symmetric and asymmetric primitives used by the API.

- Symmetric AEAD via XChaCha20-Poly1305 for server-side secrets (integration tokens, etc).
- Sealed-box helpers for user-key encrypted samples (E2E mode), where the *server*
  never holds the private key. The server's role for sealed boxes is purely transport;
  these helpers are exposed for testing.
"""
from __future__ import annotations

import binascii
import secrets

import nacl.public
import nacl.secret
import nacl.utils

from app.settings import get_settings


def _server_key() -> bytes:
    raw = get_settings().encryption_key.get_secret_value()
    try:
        key = binascii.unhexlify(raw)
    except binascii.Error as e:
        raise ValueError("ENCRYPTION_KEY must be 64 hex chars (32 bytes)") from e
    if len(key) != 32:
        raise ValueError("ENCRYPTION_KEY must decode to 32 bytes")
    return key


def encrypt_secret(plaintext: bytes) -> tuple[bytes, bytes]:
    """Encrypt operator-owned secrets (e.g. integration refresh tokens)."""
    box = nacl.secret.SecretBox(_server_key())
    nonce = nacl.utils.random(nacl.secret.SecretBox.NONCE_SIZE)
    ct = box.encrypt(plaintext, nonce).ciphertext
    return nonce, ct


def decrypt_secret(nonce: bytes, ciphertext: bytes) -> bytes:
    box = nacl.secret.SecretBox(_server_key())
    return box.decrypt(ciphertext, nonce)


def generate_pair_code() -> str:
    """Returns a 9-char shareable code like 'GH-7Q-2K-91'."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    parts = ["".join(secrets.choice(alphabet) for _ in range(2)) for _ in range(3)]
    return "GH-" + "-".join(parts)


def fingerprint_pub_key(pk_b64: str) -> str:
    """SHA-256 truncated to 16 hex chars, useful for UI device labels."""
    import hashlib
    return hashlib.sha256(pk_b64.encode()).hexdigest()[:16]


def new_keypair() -> tuple[bytes, bytes]:
    """Used in tests to fake an iOS / Android client keypair."""
    sk = nacl.public.PrivateKey.generate()
    return bytes(sk), bytes(sk.public_key)
