# Section 6 — API reference (human-readable summary)

The canonical spec is `packages/openapi/openapi.yaml`. Generated docs live at `/docs` and `/redoc` on the running API.

Below is a curated quick reference matching what the mobile apps actually call.

## Auth

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/auth/signup` | Create account + first device. Returns token pair. |
| POST | `/v1/auth/login` | Email + password. Returns token pair. |
| POST | `/v1/auth/refresh` | Rotate refresh token. |
| GET  | `/v1/auth/me` | Authenticated user. |

## Devices

| Method | Path | Purpose |
|---|---|---|
| GET    | `/v1/devices` | List devices on the account. |
| POST   | `/v1/devices` | Register/update device (upsert on `install_id`). |
| DELETE | `/v1/devices/{id}` | Revoke device. |
| POST   | `/v1/devices/pair-code` | Issue 5-minute code to link a second device. |
| POST   | `/v1/devices/redeem` | Redeem code from new device → token pair. |

## Sync

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/sync/ingest` | Push batch of samples (max 5000). Idempotent on `client_uid`. |
| GET  | `/v1/sync/samples` | Page samples (cursor = ISO timestamp). |

## Admin

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/admin/stats` | Platform stats (admin role only). |

## Error envelope

All non-2xx responses are JSON: `{ "detail": "<message>" }`. 422s additionally include the Pydantic validation error list.

## Idempotency

Every sample carries a `client_uid` (UUIDv7 from the client). The server enforces uniqueness per `(user_id, source, client_uid)`. Retried batches return the same `accepted` / `duplicates` counts; the client may safely upload the same batch any number of times.

## Cursor paging

`GET /v1/sync/samples?limit=500` returns `next_cursor` (ISO timestamp) when more samples exist. Pass it back as `?cursor=`. When `next_cursor` is null, the page is the tail of the data.

## Rate limits

See [docs/SECURITY.md](SECURITY.md#rate-limiting).
