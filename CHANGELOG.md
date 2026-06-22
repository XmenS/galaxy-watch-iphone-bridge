# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning:
[SemVer](https://semver.org/).

## [0.1.0] — 2026-06-22

First public release.

### Added
- Wear OS app that runs as a foreground service, reads steps, active calories,
  distance, floors and heart rate from Wear Health Services, stores them in a
  local Room database, and exposes them on a custom Bluetooth LE GATT service.
- iOS app that scans for the Bluetooth service, pulls samples newer than a
  per-install cursor, maps them to `HKSample` records, and writes them into
  Apple HealthKit.
- Unit tests for the BLE wire protocol parsing, watch-to-iPhone timestamp
  rebasing, and the canonical-sample to HealthKit mapping.
- GitHub Actions CI that runs the Wear OS and iOS unit tests on every push and
  pull request, plus a release workflow that attaches the Wear OS debug APK to
  each tagged release.
