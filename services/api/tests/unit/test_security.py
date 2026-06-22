import re

import pytest

from app.security.crypto import decrypt_secret, encrypt_secret, generate_pair_code
from app.security.hashing import hash_token, verify_token
from app.security.jwt import TokenError, create_access_token, decode_token
from app.security.passwords import hash_password, verify_password


def test_password_roundtrip() -> None:
    h = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", h)
    assert not verify_password("wrong", h)


def test_token_hash_constant_time() -> None:
    h = hash_token("tok_abc")
    assert verify_token("tok_abc", h)
    assert not verify_token("tok_abd", h)


def test_pair_code_format() -> None:
    code = generate_pair_code()
    assert re.fullmatch(r"GH-[A-Z2-9]{2}-[A-Z2-9]{2}-[A-Z2-9]{2}", code)


def test_jwt_roundtrip() -> None:
    import uuid
    uid = uuid.uuid4()
    tok = create_access_token(user_id=uid)
    payload = decode_token(tok)
    assert payload["sub"] == str(uid)
    assert payload["typ"] == "access"


def test_jwt_wrong_type() -> None:
    import uuid
    tok = create_access_token(user_id=uuid.uuid4())
    with pytest.raises(TokenError):
        decode_token(tok, expected_type="refresh")


def test_secret_roundtrip() -> None:
    n, ct = encrypt_secret(b"hello world")
    assert decrypt_secret(n, ct) == b"hello world"
