"""Fan-out fires after each successful ingest. Notifies webhooks and refreshes aggregates."""
import uuid

import structlog

from app.main import celery
from app.tasks._db import SessionLocal

log = structlog.get_logger("fanout")


@celery.task(name="ghb.fanout_ingest", bind=True, max_retries=5, retry_backoff=True)
def fanout_ingest(self, job_id: str) -> dict:
    job_uuid = uuid.UUID(job_id)
    with SessionLocal() as s:
        row = s.execute(
            "SELECT user_id, accepted_count FROM sync_jobs WHERE id = :id",
            {"id": str(job_uuid)},
        ).first()
        if not row:
            log.warning("fanout.job_missing", job_id=job_id)
            return {"job_id": job_id, "skipped": True}
        user_id, accepted = row[0], row[1]

    log.info("fanout.notify", job_id=job_id, user_id=str(user_id), accepted=accepted)
    # enqueue webhook deliveries
    from app.tasks.webhooks import deliver_webhooks_for_user
    deliver_webhooks_for_user.delay(str(user_id), job_id)
    return {"job_id": job_id, "user_id": str(user_id), "accepted": accepted}
