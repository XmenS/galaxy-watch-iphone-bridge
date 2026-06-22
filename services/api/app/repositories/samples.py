import base64
import uuid
from datetime import datetime

from sqlalchemy import and_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.health import HealthSample
from app.schemas.health import HealthSampleIn


def _b64d(s: str | None) -> bytes | None:
    return base64.b64decode(s) if s else None


class SampleRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def bulk_upsert(
        self, *, user_id: uuid.UUID, source: str, samples: list[HealthSampleIn]
    ) -> tuple[int, int]:
        """Returns (inserted, duplicates)."""
        if not samples:
            return 0, 0

        rows = [
            {
                "user_id": user_id,
                "source": source,
                "client_uid": s.client_uid,
                "type": s.type,
                "unit": s.unit,
                "value": s.value,
                "started_at": s.started_at,
                "ended_at": s.ended_at,
                "metadata_json": s.metadata,
                "nonce": _b64d(s.nonce_b64),
                "ciphertext": _b64d(s.ciphertext_b64),
            }
            for s in samples
        ]

        stmt = (
            pg_insert(HealthSample)
            .values(rows)
            .on_conflict_do_nothing(constraint="uq_sample_user_source_clientuid")
            .returning(HealthSample.id)
        )
        result = await self.session.execute(stmt)
        inserted_ids = list(result.scalars())
        inserted = len(inserted_ids)
        duplicates = len(rows) - inserted
        return inserted, duplicates

    async def page_for_user(
        self,
        *,
        user_id: uuid.UUID,
        since: datetime | None,
        limit: int,
        types: list[str] | None = None,
    ) -> list[HealthSample]:
        q = select(HealthSample).where(HealthSample.user_id == user_id)
        if since:
            q = q.where(HealthSample.started_at > since)
        if types:
            q = q.where(HealthSample.type.in_(types))
        q = q.order_by(HealthSample.started_at.asc(), HealthSample.id.asc()).limit(limit)
        return list((await self.session.execute(q)).scalars())

    async def count_for_user(self, user_id: uuid.UUID) -> int:
        from sqlalchemy import func
        q = select(func.count(HealthSample.id)).where(HealthSample.user_id == user_id)
        return int((await self.session.execute(q)).scalar_one())

    async def delete_all_for_user(self, user_id: uuid.UUID) -> int:
        from sqlalchemy import delete
        q = delete(HealthSample).where(HealthSample.user_id == user_id)
        result = await self.session.execute(q)
        return result.rowcount or 0
