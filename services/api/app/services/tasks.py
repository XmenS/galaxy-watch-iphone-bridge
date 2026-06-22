"""Celery task entrypoints. Re-exports tasks defined in the worker package
so that workers running off the API image can also register them."""
from app.core.celery import celery


@celery.task(name="ghb.fanout_ingest", bind=True, max_retries=3, default_retry_delay=30)
def fanout_ingest(self, job_id: str) -> dict:
    """Fan-out hook: notify webhooks / aggregate metrics for an ingest job."""
    return {"job_id": job_id, "status": "noop"}


@celery.task(name="ghb.enforce_retention")
def enforce_retention() -> dict:
    """Deletes samples beyond retention window. Real implementation in the worker package."""
    return {"deleted": 0}
