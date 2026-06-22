"""Section 10 — Sync engine.

Responsibilities:
- Deduplication via (user_id, source, client_uid) unique constraint.
- Retry-safe ingest: clients retry the same batch; duplicates count, never error.
- Conflict resolution: last-writer-wins per client_uid; metadata merge is replace.
- Offline support: clients buffer locally and flush; UUIDv7 keeps natural order.
- Incremental sync: cursor = (started_at, sample_id) returned to caller.
"""
from __future__ import annotations

import base64
import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sync import SyncJob, SyncStatus
from app.repositories.samples import SampleRepository
from app.schemas.health import (
    HealthSampleOut,
    IngestRequest,
    IngestResponse,
    SamplesPage,
)
from app.settings import get_settings


class SyncError(Exception):
    pass


class SyncService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.samples = SampleRepository(session)

    async def ingest(self, *, user_id: uuid.UUID, device_id: uuid.UUID | None, req: IngestRequest) -> IngestResponse:
        settings = get_settings()
        # E2E enforcement
        if settings.e2e_required:
            for s in req.samples:
                if s.ciphertext_b64 is None or s.nonce_b64 is None:
                    raise SyncError("E2E mode requires every sample to be encrypted")

        job = SyncJob(
            user_id=user_id,
            device_id=device_id,
            direction="ingest",
            status=SyncStatus.RUNNING.value,
            started_at=datetime.now(timezone.utc),
        )
        self.session.add(job)
        await self.session.flush()

        try:
            inserted, duplicates = await self.samples.bulk_upsert(
                user_id=user_id, source=req.source, samples=req.samples
            )
            job.accepted_count = inserted
            job.duplicate_count = duplicates
            job.rejected_count = 0
            job.status = SyncStatus.SUCCESS.value
        except Exception as e:
            job.status = SyncStatus.FAILED.value
            job.error = str(e)[:1024]
            job.finished_at = datetime.now(timezone.utc)
            await self.session.flush()
            raise
        job.finished_at = datetime.now(timezone.utc)
        await self.session.flush()

        return IngestResponse(
            job_id=job.id,
            accepted=job.accepted_count,
            duplicates=job.duplicate_count,
            rejected=job.rejected_count,
        )

    async def page(
        self,
        *,
        user_id: uuid.UUID,
        cursor: str | None,
        limit: int = 500,
        types: list[str] | None = None,
    ) -> SamplesPage:
        since: datetime | None = None
        if cursor:
            try:
                since = datetime.fromisoformat(cursor)
            except ValueError as e:
                raise SyncError("invalid cursor") from e

        rows = await self.samples.page_for_user(
            user_id=user_id, since=since, limit=limit, types=types
        )
        items = [
            HealthSampleOut.model_validate(
                {
                    "id": r.id,
                    "client_uid": r.client_uid,
                    "source": r.source,
                    "type": r.type,
                    "started_at": r.started_at,
                    "ended_at": r.ended_at,
                    "unit": r.unit,
                    "value": r.value,
                    "metadata": r.metadata_json,
                    "nonce_b64": base64.b64encode(r.nonce).decode() if r.nonce else None,
                    "ciphertext_b64": base64.b64encode(r.ciphertext).decode() if r.ciphertext else None,
                }
            )
            for r in rows
        ]
        next_cursor = rows[-1].started_at.isoformat() if len(rows) == limit else None
        return SamplesPage(items=items, next_cursor=next_cursor)
