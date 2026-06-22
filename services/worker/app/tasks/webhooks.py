import hashlib
import hmac
import time

import httpx
import structlog
from sqlalchemy import text

from app.main import celery
from app.settings import settings
from app.tasks._db import SessionLocal

log = structlog.get_logger("webhooks")


@celery.task(name="ghb.deliver_webhooks_for_user", bind=True, max_retries=5, retry_backoff=True)
def deliver_webhooks_for_user(self, user_id: str, job_id: str) -> dict:
    """Look up webhook integrations for a user and POST a notification per endpoint."""
    delivered = 0
    with SessionLocal() as s:
        rows = s.execute(
            text(
                "SELECT id, config FROM integrations "
                "WHERE user_id = :u AND kind = 'webhook' AND enabled = true"
            ),
            {"u": user_id},
        ).all()
    for row in rows:
        url = (row.config or {}).get("url")
        secret = (row.config or {}).get("secret", "")
        if not url:
            continue
        body = {"event": "sync.ingest", "user_id": user_id, "job_id": job_id, "ts": int(time.time())}
        import json

        raw = json.dumps(body, separators=(",", ":")).encode()
        sig = hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
        try:
            with httpx.Client(timeout=settings.webhook_timeout_seconds) as c:
                r = c.post(
                    url,
                    content=raw,
                    headers={
                        "Content-Type": "application/json",
                        "X-GHB-Signature": f"sha256={sig}",
                    },
                )
                r.raise_for_status()
                delivered += 1
        except Exception as e:
            log.warning("webhook.failed", url=url, error=str(e))
            raise self.retry(exc=e)
    return {"delivered": delivered}
