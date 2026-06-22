from pydantic import PostgresDsn, RedisDsn, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: PostgresDsn = "postgresql+asyncpg://ghb:ghb@postgres:5432/ghb"
    redis_url: RedisDsn = "redis://redis:6379/0"
    encryption_key: SecretStr = SecretStr("00" * 32)

    retention_days: int = 365 * 2
    webhook_timeout_seconds: int = 10


settings = Settings()
