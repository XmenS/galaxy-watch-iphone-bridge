from celery import Celery

from app.settings import get_settings


def make_celery() -> Celery:
    s = get_settings()
    app = Celery(
        "ghb",
        broker=str(s.redis_url),
        backend=str(s.redis_url),
        include=["app.services.tasks"],
    )
    app.conf.update(
        task_serializer="json",
        result_serializer="json",
        accept_content=["json"],
        timezone="UTC",
        enable_utc=True,
        task_acks_late=True,
        worker_prefetch_multiplier=4,
        task_default_queue="default",
    )
    return app


celery = make_celery()
