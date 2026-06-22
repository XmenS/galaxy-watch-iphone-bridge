from datetime import datetime, timedelta, timezone

import structlog
from sqlalchemy import text

from app.main import celery
from app.settings import settings
from app.tasks._db import SessionLocal

log = structlog.get_logger("retention")


@celery.task(name="ghb.enforce_retention", bind=True)
def enforce_retention(self) -> dict:
    """Delete samples older than the retention window. Hard delete; clients keep
    their own copies on-device."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.retention_days)
    deleted_samples = 0
    deleted_jobs = 0
    with SessionLocal() as s:
        r = s.execute(
            text("DELETE FROM health_samples WHERE started_at < :c"), {"c": cutoff}
        )
        deleted_samples = r.rowcount or 0
        r = s.execute(
            text("DELETE FROM sync_jobs WHERE created_at < :c AND status IN ('success','failed','cancelled')"),
            {"c": cutoff},
        )
        deleted_jobs = r.rowcount or 0
        s.commit()
    log.info("retention.swept", samples=deleted_samples, jobs=deleted_jobs, cutoff=cutoff.isoformat())
    return {"samples": deleted_samples, "jobs": deleted_jobs}
