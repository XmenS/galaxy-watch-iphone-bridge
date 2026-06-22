# Section 2 — Architecture

## 2.1 High-level

```mermaid
flowchart LR
  subgraph Wrist
    GW[Galaxy Watch]
  end
  subgraph Android Phone
    SH[Samsung Health]
    HC[Health Connect]
    AND[Android Companion App]
  end
  subgraph Backend
    CD[(Caddy / TLS)]
    API[FastAPI API]
    W[Celery Worker]
    PG[(PostgreSQL)]
    R[(Redis)]
    S3[(S3 - opt., blob samples)]
  end
  subgraph iPhone
    IOS[iPhone Companion App]
    HK[HealthKit]
  end

  GW -- BLE --> SH
  SH -- write --> HC
  AND -- read --> HC
  AND -- HTTPS / TLS --> CD
  CD --> API
  API --> PG
  API --> R
  W --> R
  W --> PG
  W --> S3
  IOS -- HTTPS / TLS --> CD
  CD --> API
  IOS -- write --> HK
```

## 2.2 Sequence: end-to-end sync

```mermaid
sequenceDiagram
  autonumber
  participant W as Galaxy Watch
  participant SH as Samsung Health
  participant HC as Health Connect
  participant A as Android App
  participant API as Backend API
  participant Q as Worker (Celery)
  participant I as iPhone App
  participant HK as HealthKit

  W->>SH: BLE sample (HR, steps, sleep)
  SH->>HC: writeRecords()
  Note over A: WorkManager fires every 15 min
  A->>HC: readRecords(since=last_cursor)
  HC-->>A: List<HealthRecord>
  A->>A: map → canonical sample
  A->>A: encrypt(sample, user_pub_key)
  A->>API: POST /v1/sync/ingest (batch, client_uid per sample)
  API->>API: upsert (user_id, source, client_uid)
  API-->>A: 202 {job_id, accepted}
  API->>Q: enqueue fan-out job
  Q->>Q: aggregate by destination
  Note over I: BGAppRefreshTask fires
  I->>API: GET /v1/samples?since=cursor&for=ios
  API-->>I: encrypted samples + cursor
  I->>I: decrypt(user_priv_key)
  I->>HK: HKHealthStore.save(samples)
  HK-->>I: success
  I->>API: PATCH /v1/samples/ack {cursor}
```

## 2.3 Sequence: device pairing

```mermaid
sequenceDiagram
  participant U as User
  participant A as Android App
  participant API as Backend
  participant I as iPhone App

  U->>A: Sign up (email+password OR magic link)
  A->>API: POST /v1/auth/signup
  API-->>A: {access, refresh}
  A->>A: generate Curve25519 keypair (X25519)
  A->>API: POST /v1/devices {pub_key, kind:"android"}
  API-->>A: device_id

  U->>A: "Pair iPhone"
  A->>API: POST /v1/devices/pair-code
  API-->>A: {code:"GH-7Q-2K-91", expires_at}
  A-->>U: shows code

  U->>I: Open iPhone app, enter code
  I->>API: POST /v1/devices/redeem {code}
  API-->>I: {access, refresh, peer_pub_key}
  I->>I: generate keypair, exchange with peer
  I->>API: POST /v1/devices {pub_key, kind:"ios"}
```

## 2.4 Data flow contract

Canonical sample schema (lingua franca between Android and iOS):

```json
{
  "client_uid": "01HV2P7K6E5R3Q8M2J9XYZ0001",   // UUIDv7 from Android
  "source": "samsung-health",
  "type": "heart_rate",
  "unit": "bpm",
  "value": 72.0,
  "started_at": "2026-06-18T14:30:00Z",
  "ended_at":   "2026-06-18T14:30:01Z",
  "device": { "manufacturer": "Samsung", "model": "Galaxy Watch7" },
  "metadata": { "samsung_uid": "...", "confidence": 0.99 }
}
```

Encryption envelope (when E2E mode on):

```json
{
  "client_uid": "01HV2P7K6E5R3Q8M2J9XYZ0001",
  "type": "heart_rate",
  "started_at": "2026-06-18T14:30:00Z",
  "ended_at":   "2026-06-18T14:30:01Z",
  "nonce_b64": "...",
  "ciphertext_b64": "..."
}
```

Server sees only the outer envelope. Type and timestamps are intentionally plaintext so the server can dedupe and index without decryption.

## 2.5 Component responsibilities

| Component | Owns | Does NOT own |
|---|---|---|
| Android app | Health Connect reads, mapping, encryption, upload, retry queue | Display analytics, push notifications to iPhone |
| iPhone app | Download, decryption, HealthKit writes, dedupe vs HealthKit anchor | Reading Health Connect |
| Backend API | Auth, device registry, sample storage, fan-out, audit log | Decryption, HealthKit write |
| Worker | Aggregation, retention enforcement, webhook delivery | User-facing request handling |
| Postgres | Source of truth for everything except blob bodies | Sample blobs (over 1KB → S3) |
| Redis | Job queue, rate-limit counters, ephemeral sync cursors | Persistent data |
