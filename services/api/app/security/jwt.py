import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt

from app.settings import get_settings


class TokenError(Exception):
    pass


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def create_access_token(
    *, user_id: uuid.UUID, device_id: uuid.UUID | None = None, scopes: list[str] | None = None
) -> str:
    s = get_settings()
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "did": str(device_id) if device_id else None,
        "scp": scopes or [],
        "typ": "access",
        "iat": int(_now().timestamp()),
        "exp": int((_now() + timedelta(seconds=s.jwt_access_ttl_seconds)).timestamp()),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, s.jwt_secret.get_secret_value(), algorithm=s.jwt_algorithm)


def create_refresh_token(*, user_id: uuid.UUID, device_id: uuid.UUID | None = None) -> tuple[str, datetime]:
    s = get_settings()
    expires = _now() + timedelta(seconds=s.jwt_refresh_ttl_seconds)
    payload = {
        "sub": str(user_id),
        "did": str(device_id) if device_id else None,
        "typ": "refresh",
        "iat": int(_now().timestamp()),
        "exp": int(expires.timestamp()),
        "jti": str(uuid.uuid4()),
    }
    token = jwt.encode(payload, s.jwt_secret.get_secret_value(), algorithm=s.jwt_algorithm)
    return token, expires


def decode_token(token: str, expected_type: str = "access") -> dict[str, Any]:
    s = get_settings()
    try:
        payload = jwt.decode(
            token,
            s.jwt_secret.get_secret_value(),
            algorithms=[s.jwt_algorithm],
            options={"require": ["exp", "iat", "sub", "typ"]},
        )
    except jwt.ExpiredSignatureError as e:
        raise TokenError("token expired") from e
    except jwt.InvalidTokenError as e:
        raise TokenError(f"invalid token: {e}") from e
    if payload.get("typ") != expected_type:
        raise TokenError("wrong token type")
    return payload
