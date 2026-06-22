# Security Policy

## Supported versions

| Version       | Supported |
|---------------|-----------|
| 0.x (current) | yes       |

## Reporting a vulnerability

Please do not file a public issue. Use [GitHub Security Advisories](../../security/advisories/new) on this repository, or email the maintainer directly if the advisory feature is not available.

We will try to acknowledge within 72 hours and ship a fix or mitigation within 90 days. Reporters are credited in release notes unless they ask to stay anonymous.

## What is in scope

* The Wear OS app at `apps/wearos/`.
* The iOS app at `apps/ios/`.
* The Bluetooth wire protocol described in `docs/ARCHITECTURE.md`.

## What is out of scope

* Anything Samsung Health or Apple Health does on their own. We just read what their public APIs hand us.
* User mistakes during install (for example sideloading the watch APK to a device that is not theirs).

## Security model in plain words

* There is no backend. The watch and the iPhone talk directly over Bluetooth LE in your home. Nothing reaches the public internet.
* No account, no telemetry. The apps do not phone home.
* Health data is written into Apple HealthKit on the iPhone using the same APIs every other Health app uses. Apple controls the keys, permissions and storage.
* The Bluetooth service UUID is fixed and unique to this app. If you want to harden against an attacker within Bluetooth range, do not run the watch app outside trusted places.
