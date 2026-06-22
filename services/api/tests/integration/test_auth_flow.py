import uuid

import pytest


@pytest.mark.asyncio
async def test_signup_login_refresh(client, install_id):
    email = f"u-{uuid.uuid4().hex[:8]}@example.com"

    r = await client.post(
        "/v1/auth/signup",
        json={
            "email": email,
            "password": "supersecurepass1!",
            "install_id": install_id,
            "device_kind": "android",
            "device_label": "Pixel 8",
        },
    )
    assert r.status_code == 201, r.text
    tokens = r.json()
    assert {"access_token", "refresh_token"} <= tokens.keys()

    r = await client.post(
        "/v1/auth/login",
        json={
            "email": email,
            "password": "supersecurepass1!",
            "install_id": install_id,
            "device_kind": "android",
        },
    )
    assert r.status_code == 200, r.text
    refresh = r.json()["refresh_token"]

    r = await client.post("/v1/auth/refresh", json={"refresh_token": refresh})
    assert r.status_code == 200, r.text
    new = r.json()
    assert new["access_token"] != tokens["access_token"]


@pytest.mark.asyncio
async def test_login_wrong_password(client, install_id):
    email = f"u-{uuid.uuid4().hex[:8]}@example.com"
    await client.post(
        "/v1/auth/signup",
        json={
            "email": email,
            "password": "supersecurepass1!",
            "install_id": install_id,
            "device_kind": "android",
        },
    )
    r = await client.post(
        "/v1/auth/login",
        json={
            "email": email,
            "password": "wrong-pass-1234",
            "install_id": install_id,
            "device_kind": "android",
        },
    )
    assert r.status_code == 401
