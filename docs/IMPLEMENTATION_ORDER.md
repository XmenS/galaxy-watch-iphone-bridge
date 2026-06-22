# Section 19 — Implementation order

## Day 1
- Provision Apple Developer team + HealthKit entitlement request.
- Provision Samsung Galaxy device + watch loaner pool.
- `make install && make dev` boots locally; confirm `/health` returns 200.
- Run `alembic upgrade head` and `pytest`.

## Week 1
- API surface: signup, login, refresh, devices upsert, ingest, samples paging — done in this scaffold.
- Android shell: HC permissions, single manual sync round-trip.
- iOS shell: pair-code redeem, HealthKit auth, single manual sync round-trip.
- Docker compose stack runs end-to-end on a developer laptop.

## Week 2
- WorkManager periodic + iOS BGAppRefresh wired and verified on real devices.
- All 5 alpha metric types (steps, HR, sleep, SpO₂, active calories) mapped both directions.
- CI green: backend tests, Android unit tests, iOS XCTest, Docker multi-arch build.

## Month 1
- Phase 1 milestones above complete.
- Hosted staging environment: `terraform apply` against a fresh AWS account.
- Internal TestFlight build seeded to 5 employees.

## Month 2
- Phase 2 begins. App Store submission. Play Store Health Connect declaration filed.
- E2E encryption mode shipped behind feature flag.
- Helm chart published.

## Month 3
- App Store + Play Store approvals (rework 1 round of rejections).
- Public Beta launch.
- Begin moving repo toward public release: clean git history, remove any internal references, finalize OSS docs.
