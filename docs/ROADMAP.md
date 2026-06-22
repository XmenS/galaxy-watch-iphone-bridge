# Section 18 — Roadmap

All dates anchored to **2026-06-18** (today). Timelines are honest estimates assuming a 3-person team (1 backend, 1 mobile, 1 generalist/devops).

## Phase 1 — Private Beta (8 weeks, target 2026-08-13)

**Goal:** End-to-end sync of 5 metrics (steps, heart rate, sleep stages, SpO₂, active calories) Galaxy Watch → iPhone HealthKit for 20 invited testers.

| Milestone | Owner | Done when |
|---|---|---|
| Backend MVP: signup/login/devices/ingest/samples paging | Backend | Coverage ≥80%, ingest dedupes, paging cursor works. |
| Android: HC permissions + WorkManager pulls + uploads | Mobile | Background sync runs for 24h with no battery complaint on Pixel 8 + Galaxy S24. |
| iOS: pair-code redeem + HealthKit writes + BGAppRefresh | Mobile | Manual sync writes data visible in Apple Health; background fires ≥4×/day. |
| Docker stack + install.sh | DevOps | One-line install on a fresh Hetzner CX22 in ≤5 min. |
| TestFlight build | Mobile | 100% pass internal review. |
| Closed-beta onboarding doc | All | Tester can install both apps + sync in <15 min. |

**Dependencies / blockers**
- Apple Developer account & HealthKit entitlement (must be in place before week 1).
- Samsung Galaxy device pool (2 watches + 2 phones minimum).

## Phase 2 — Public Beta (12 weeks, target 2026-11-05)

**Goal:** 500 self-hosters, 1000 cloud users.

- Hosted production deployment (Terraform AWS, ~$200/mo at this scale).
- App Store + Play Store submissions (allow 2 reviews + 1 rejection rebound).
- All 25 canonical metric types mapped, including workouts.
- E2E encryption enabled by default for cloud tier.
- Helm chart in artifacthub.
- Status page + Statuspage-style incident comms.
- Docs site live at `docs.galaxyhealthbridge.dev`.

**Dependencies**
- Play Store Health Connect declaration approved.
- Apple HealthKit privacy review approved.

## Phase 3 — Open-Source GA (12 weeks, target 2027-01-28)

**Goal:** Public MIT release with a thriving contributor base.

- Flip repo to public.
- File CVE process via huntr.dev.
- Plugin SDK for community sources (Garmin, Fitbit, Oura, WHOOP).
- Hosted plan opens to general public ($5/mo personal, $15/mo family).
- Three external committers on the steering committee.
- 50+ Discord active members or equivalent forum metric.

## Post-GA quarterly themes

- Q2 2027 — Webhook integrations + Zapier-style data export.
- Q3 2027 — Multi-watch support (mix Galaxy + Pixel Watch).
- Q4 2027 — Cross-platform analytics dashboard (privacy-preserving).
