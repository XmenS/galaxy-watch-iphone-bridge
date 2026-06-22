from functools import lru_cache
from typing import Literal

from pydantic import Field, PostgresDsn, RedisDsn, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # ---- runtime
    env: Literal["dev", "test", "staging", "prod"] = "dev"
    log_level: Literal["debug", "info", "warning", "error"] = "info"
    public_url: str = "http://localhost:8000"

    # ---- datastores
    database_url: PostgresDsn = Field(default="postgresql+asyncpg://ghb:ghb@postgres:5432/ghb")
    redis_url: RedisDsn = Field(default="redis://redis:6379/0")

    # ---- security
    jwt_secret: SecretStr = SecretStr("change-me-in-prod")
    jwt_algorithm: Literal["HS256", "RS256", "EdDSA"] = "HS256"
    jwt_access_ttl_seconds: int = 60 * 15           # 15 min
    jwt_refresh_ttl_seconds: int = 60 * 60 * 24 * 30  # 30 days
    encryption_key: SecretStr = SecretStr("change-me-32-bytes-hex" + "0" * 12)  # 64 hex chars
    argon2_time_cost: int = 3
    argon2_memory_kib: int = 64 * 1024
    argon2_parallelism: int = 4

    # ---- pairing
    pair_code_ttl_seconds: int = 300                # 5 min
    pair_code_attempts_max: int = 5

    # ---- rate limits
    rate_limit_signup_per_ip: str = "5/minute"
    rate_limit_login_per_ip: str = "10/minute"
    rate_limit_ingest_per_user: str = "120/minute"

    # ---- E2E mode
    e2e_required: bool = False                       # cloud sets true; self-host false by default

    # ---- storage
    sample_blob_threshold_bytes: int = 1024
    s3_bucket: str | None = None
    s3_region: str | None = None

    # ---- observability
    otel_endpoint: str | None = None
    prometheus_enabled: bool = True

    # ---- CORS
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])


@lru_cache
def get_settings() -> Settings:
    return Settings()
