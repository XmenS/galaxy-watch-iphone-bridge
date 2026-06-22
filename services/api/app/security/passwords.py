from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.settings import get_settings


def _hasher() -> PasswordHasher:
    s = get_settings()
    return PasswordHasher(
        time_cost=s.argon2_time_cost,
        memory_cost=s.argon2_memory_kib,
        parallelism=s.argon2_parallelism,
    )


def hash_password(plain: str) -> str:
    return _hasher().hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return _hasher().verify(hashed, plain)
    except VerifyMismatchError:
        return False
