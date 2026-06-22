"""Seed the dev DB with one admin user + a few sample rows for local UI smoke tests."""
import asyncio
import os
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://ghb:ghb@localhost:5432/ghb")

from app.database import Base                              # noqa: E402
from app.models.health import HealthSample                  # noqa: E402
from app.models.user import User, UserRole                  # noqa: E402
from app.security.passwords import hash_password            # noqa: E402


async def main() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    sm = async_sessionmaker(engine, expire_on_commit=False)
    async with sm() as s:
        admin = User(
            email="admin@local",
            password_hash=hash_password("supersecurepass1!"),
            role=UserRole.ADMIN.value,
            is_verified=True,
        )
        s.add(admin)
        await s.flush()

        now = datetime.now(timezone.utc)
        for i in range(100):
            s.add(HealthSample(
                user_id=admin.id,
                source="samsung-health",
                client_uid=f"seed-{i}",
                type="heart_rate",
                unit="bpm",
                value=60 + (i % 30),
                started_at=now - timedelta(minutes=i),
                ended_at=now - timedelta(minutes=i),
                metadata_json={},
            ))
        await s.commit()
    print("seeded admin@local / supersecurepass1!")


if __name__ == "__main__":
    asyncio.run(main())
