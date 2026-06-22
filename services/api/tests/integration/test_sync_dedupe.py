import uuid
from datetime import datetime, timedelta, timezone

import pytest


async def _signup(client, install_id):
    email = f"u-{uuid.uuid4().hex[:8]}@example.com"
    r = await client.post(
        "/v1/auth/signup",
        json={
            "email": email,
            "password": "supersecurepass1!",
            "install_id": install_id,
            "device_kind": "android",
        },
    )
    return r.json()["access_token"]


def _sample(uid: str, ts: datetime, value: float = 72.0) -> dict:
    return {
        "client_uid": uid,
        "source": "samsung-health",
        "type": "heart_rate",
        "unit": "bpm",
        "value": value,
        "started_at": ts.isoformat(),
        "ended_at": ts.isoformat(),
        "metadata": {},
    }


@pytest.mark.asyncio
async def test_ingest_dedupes_on_client_uid(client, install_id):
    token = await _signup(client, install_id)
    headers = {"Authorization": f"Bearer {token}"}
    now = datetime.now(timezone.utc)

    samples = [_sample(f"uid-{i}", now - timedelta(minutes=i)) for i in range(50)]
    r1 = await client.post(
        "/v1/sync/ingest",
        json={"source": "samsung-health", "samples": samples},
        headers=headers,
    )
    assert r1.status_code == 202, r1.text
    assert r1.json()["accepted"] == 50
    assert r1.json()["duplicates"] == 0

    # Replay full batch — server must accept request, count 50 dupes.
    r2 = await client.post(
        "/v1/sync/ingest",
        json={"source": "samsung-health", "samples": samples},
        headers=headers,
    )
    assert r2.status_code == 202
    assert r2.json()["accepted"] == 0
    assert r2.json()["duplicates"] == 50


@pytest.mark.asyncio
async def test_sample_paging_cursor(client, install_id):
    token = await _signup(client, install_id)
    headers = {"Authorization": f"Bearer {token}"}
    now = datetime.now(timezone.utc)

    samples = [_sample(f"p-{i}", now + timedelta(minutes=i), value=float(i)) for i in range(120)]
    await client.post(
        "/v1/sync/ingest",
        json={"source": "samsung-health", "samples": samples},
        headers=headers,
    )

    r = await client.get("/v1/sync/samples?limit=50", headers=headers)
    body = r.json()
    assert len(body["items"]) == 50
    assert body["next_cursor"] is not None
    r2 = await client.get(
        f"/v1/sync/samples?limit=200&cursor={body['next_cursor']}",
        headers=headers,
    )
    assert len(r2.json()["items"]) == 70
