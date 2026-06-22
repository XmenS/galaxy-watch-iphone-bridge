# Developer Testing

> Looking for the end-to-end "is it working with my watch and iPhone?" guide? See [`TESTING.md`](TESTING.md).

This file documents the automated test layout for contributors.

Coverage target: **90%** across business logic. CI gate currently set at 80% on the API package; we'll raise as the test suite grows.

## Unit tests

| Stack | Tool | Where |
|---|---|---|
| Backend | pytest + pytest-asyncio | `services/api/tests/unit` |
| iOS | XCTest | `apps/ios/GalaxyHealthBridgeTests` |
| Android | JUnit4 + Truth + MockK | `apps/android/app/src/test/kotlin` |

Examples shipped:
- `services/api/tests/unit/test_security.py` — argon2, JWT, HMAC token hashing, pair-code format, AEAD round-trip.
- `apps/ios/GalaxyHealthBridgeTests/CanonicalSampleMappingTests.swift` — HK quantity + category mapping.
- `apps/android/app/src/test/kotlin/dev/galaxyhealthbridge/android/CanonicalSampleTest.kt` — wire-format serialization.

## Integration tests

- `services/api/tests/integration/test_auth_flow.py` — signup → login → refresh.
- `services/api/tests/integration/test_sync_dedupe.py` — ingest dedupe contract + cursor paging.

These spin up a real Postgres via the GHA service container; locally use `docker compose up -d postgres redis`.

## End-to-end

Live in `tests/e2e/` — a Playwright-style harness driving the API directly, plus separate Maestro flows for Android UI smoke tests:

```bash
make e2e
```

## Load

`tests/load/k6/` (added in Phase 2): 50 RPS sustained on `/v1/sync/ingest` for 10 min, p95 < 250 ms is the budget.

## Manual / device matrix (required before any release)

| Device | Watch | OS | Health Connect coverage |
|---|---|---|---|
| Pixel 8 Pro | Galaxy Watch 6 | Android 14 | steps, HR, sleep, SpO₂, calories |
| Galaxy S24 | Galaxy Watch 7 | Android 14 | + stress, body composition |
| iPhone 15 | n/a | iOS 17 | all destination writes |
| iPhone SE 3 | n/a | iOS 16 | minimum supported iOS |

## What we deliberately don't test in CI

- HealthKit writes (requires real iPhone, signed app). Run nightly on a self-hosted macOS runner with a paired device.
- Health Connect reads on emulators (HC support in emulator is incomplete). Manual test on real device matrix.
