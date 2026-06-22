# Section 1 — Executive Feasibility Report

> Honest reality check before anyone writes a line of code. Re-read this any time you're tempted to design something that depends on capabilities the platforms don't actually grant.

## TL;DR

- **VALIDATED:** Reading Galaxy Watch data on Android via Health Connect (Samsung Health writes most metrics to Health Connect since 2023).
- **VALIDATED:** Writing data to Apple HealthKit from a third-party iOS app.
- **BLOCKER:** Writing to HealthKit from a server is *impossible*. The iPhone app is mandatory.
- **RISK:** Samsung Health Data SDK is partner-gated for some advanced metrics (stress, SpO₂ historical, ECG). Health Connect coverage of these depends on Samsung Health version installed on the user's phone.
- **ASSUMPTION:** Users have both an Android phone (with Galaxy Watch paired) **and** an iPhone. This is the entire use case.

---

## A. What is possible today — VALIDATED

| Capability | Source | Notes |
|---|---|---|
| Read steps, heart rate, sleep, distance, calories, exercise sessions from Galaxy Watch | **Health Connect** on Android 14+ (or via APK on Android 9+) | Samsung Health auto-syncs these to Health Connect on supported regions/devices. |
| Read SpO₂, body composition, blood oxygen samples | **Health Connect** | Available depending on Samsung Health version. Coverage improving each release. |
| Write all standard quantity samples (steps, HR, distance, energy, etc.) and category samples (sleep stages, mindful minutes) to HealthKit | **HealthKit API** on iOS 13+ | Requires user permission per metric type. |
| Background delivery for Health Connect reads (Android) | `HealthConnectClient.permissionController` + `WorkManager` periodic worker | 15-minute minimum interval (system-enforced). |
| Background fetch on iOS to pull from backend → write to HealthKit | `BGAppRefreshTask` + `BGProcessingTask` | iOS schedules opportunistically; not guaranteed timing. |
| OAuth2 / device-pair authentication for two mobile clients linked to one account | Standard FastAPI + JWT | Trivial. |
| End-to-end encryption of health samples in transit (TLS) and at rest (libsodium sealed boxes) | Yes | Server holds ciphertext only if E2E mode enabled. |

## B. What is impossible today — BLOCKER

| Want | Why impossible |
|---|---|
| Write to Apple HealthKit from the server | Apple does not expose a server-side API. HealthKit is on-device only, accessible only via signed apps installed by the user. |
| Read Apple HealthKit from the server | Same. Only an iOS app, with user permission, can read HealthKit. |
| Pull live ECG strips from Galaxy Watch outside Samsung's partner program | Samsung Health Data SDK gates ECG behind partner approval. |
| Run a background service on iOS that polls the network every minute | iOS background execution is opportunistic. Reliable cadence is ~hours, not minutes. We get ~6–12 syncs/day reliably. |
| Distribute the iOS app outside the App Store at scale | TestFlight (100 internal, 10k external testers) is fine for beta. GA requires App Store review. |
| Avoid the iPhone app entirely | See block 1. There is no path. |

## C. What requires validation — ASSUMPTION

| Item | How to validate | Owner |
|---|---|---|
| Samsung Health → Health Connect coverage in target regions (US/EU/IN/KR) | Manual test on Galaxy Watch 6/7 + Galaxy S23/S24 in each region. Document which metrics propagate. | Android lead |
| HealthKit accepts our metric mapping (units, source provenance) without warnings | Build mapper, run `HKHealthStore.save(_:)` on each canonical type, log results. | iOS lead |
| iOS background fetch cadence is acceptable to users | Field test for 2 weeks with 10 alpha users, measure p50/p95 sync latency. | QA |
| Battery cost of the Android WorkManager job at 15-min cadence | Battery Historian profile on Pixel + Galaxy device. | Android lead |
| Samsung Health Data SDK eligibility for non-partner use | Apply to Samsung Developer portal; document response. | PM |

## D. App Store / Play Store risks — RISK

| Risk | Mitigation |
|---|---|
| Apple rejects for "duplicating system functionality" | Position as cross-ecosystem bridge — clearly not duplicating HealthKit. Disclose data flow in app store description and in-app onboarding. |
| Apple rejects for unclear health-data purpose | Implement full `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` strings. Show explicit consent screens with per-metric toggles. |
| Apple rejects for background usage abuse | Use `BGAppRefreshTask` with conservative scheduling. No `silent push` for background work. |
| Play Store rejects for `READ_HEALTH_DATA` without justification | Submit Health Connect declaration form with purpose, data retention, deletion flow. |
| Samsung Health TOS prohibits resale of data | We don't resell. Document in privacy policy + terms. Self-hosted by default ensures the user owns their data. |

## E. Samsung ecosystem risks — RISK

| Risk | Mitigation |
|---|---|
| Samsung changes Health Connect propagation behavior | Pin to specific Samsung Health versions in CI; monitor Samsung release notes. Add telemetry on coverage delta. |
| Galaxy Watch firmware update breaks a metric | Integration test matrix per Watch model. Fail open: skip unknown metrics, don't crash. |
| User has Samsung Health installed but disabled Health Connect sync | Onboarding flow detects this and walks the user through enabling it (link to Samsung Health → Settings → Health Connect). |
| Samsung partner SDK access denied | Restrict roadmap to Health Connect-exposed metrics. Document deferred metrics. |

## F. Privacy risks — RISK

| Risk | Mitigation |
|---|---|
| Server operator can read user health data | E2E encryption mode: per-user keypair generated on first device; samples encrypted on Android, decrypted on iOS. Server stores ciphertext + opaque metadata. Default ON for cloud, optional for self-host. |
| Plaintext leak through logs | `LOG_LEVEL=info` strips all sample bodies. `pino`-style log scrubber. CI lint: forbid `logger.*(sample)`. |
| Account compromise → data exfil | TOTP 2FA mandatory for cloud. Optional for self-host (default on). |
| GDPR / DPDP (India) right-to-deletion | `DELETE /v1/users/me` hard-deletes all rows + S3 objects within 30 days. Audit log retains hash-only references. |
| Children's data (under 13) | Not supported. Onboarding asks DOB; under-13 accounts refused. |

## G. Security risks — RISK

| Risk | Mitigation |
|---|---|
| Backend compromise → mass data leak | Per-user encryption keys. Defense in depth: TLS, libsodium sealed boxes, Postgres at rest encryption, S3 SSE-KMS. |
| Stolen mobile device → unauthorized sync | Device-pair tokens revocable from dashboard. Mandatory device PIN/biometric to open the app. |
| Replay attacks on `/v1/sync/ingest` | Each sample carries a `client_uid` (UUIDv7). Server upserts on `(user_id, source, client_uid)` — idempotent. |
| Plugin / dependency supply chain | Pinned versions, `pip-audit` + `npm audit` in CI, Dependabot weekly, signed Docker images (cosign). |

---

## Decision log

- **2026-06-18:** HealthKit server write confirmed impossible. iPhone companion is non-negotiable.
- **2026-06-18:** Health Connect chosen over direct Samsung Health Data SDK as the primary Android data source. SDK is a fallback for metrics HC doesn't cover.
- **2026-06-18:** E2E encryption is the default for the hosted version. Self-hosted users can disable it for simpler admin.
