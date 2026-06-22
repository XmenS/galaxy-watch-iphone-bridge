# Contributing to Galaxy Health Bridge

Thanks for wanting to help. This project is MIT licensed and welcomes pull requests.

## Quick start

```bash
git clone <repo> galaxy-health-bridge
cd galaxy-health-bridge
```

Then pick the side you want to work on. The two apps are independent.

## Where things live

| If you want to change         | Open files in                              |
|-------------------------------|--------------------------------------------|
| iOS HealthKit, UI             | `apps/ios/GalaxyHealthBridge/`             |
| Wear OS (the watch side)      | `apps/wearos/app/src/main/kotlin/`         |
| BLE wire protocol             | both apps, plus `docs/ARCHITECTURE.md`     |
| Docs                          | `docs/`                                    |

## Coding style

* **Swift:** SwiftUI plus async/await. Stay away from Combine unless a system API forces you.
* **Kotlin:** Coroutines and Flow, Compose for UI, Room for storage.
* **Tests:** Required for any non trivial behavior change. Existing tests live in `apps/ios/GalaxyHealthBridgeTests/` and `apps/wearos/app/src/test/kotlin/`.
* **Commits:** Conventional Commits style is appreciated (`feat:`, `fix:`, `chore:`, `docs:`).

## Pull request flow

1. Fork, then branch off `main`.
2. Open a draft PR early so CI runs and we can see what you are working on.
3. Push the green CI run plus your test results.
4. At least one maintainer approves before merge.

## Health data is sensitive

This is a hard rule. Never log a sample value, never commit any fixture file that contains real metrics from a real device, and never push test data that includes a real person's heart rate, steps, sleep, or anything else recorded by a wearable. Use synthetic data for tests.

## Security issues

Please do not file public issues for security bugs. The process is in `SECURITY.md`.
