from celery import Celery
from celery.schedules import crontab

from app.settings import settings

celery = Celery(
    "ghb-worker",
    broker=str(settings.redis_url),
    backend=str(settings.redis_url),
    include=["app.tasks.fanout", "app.tasks.retention", "app.tasks.webhooks"],
)
celery.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,
    worker_prefetch_multiplier=4,
    task_routes={
        "ghb.fanout_ingest": {"queue": "sync"},
        "ghb.deliver_webhook": {"queue": "sync"},
        "ghb.enforce_retention": {"queue": "retention"},
    },
    beat_schedule={
        "retention-nightly": {
            "task": "ghb.enforce_retention",
            "schedule": crontab(minute=0, hour=3),
        },
    },
)
