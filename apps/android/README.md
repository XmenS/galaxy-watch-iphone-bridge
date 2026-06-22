# Galaxy Health Bridge — Android Companion

Native Kotlin app. Reads Galaxy Watch metrics via Health Connect and uploads to the backend.

## Requirements

- Android Studio Hedgehog (2023.1.1) or newer
- JDK 17
- Android SDK 34 (compileSdk) / 26 (minSdk)
- Real Galaxy device + Galaxy Watch for end-to-end testing (Health Connect is sparse in emulators)
- Samsung Health version that propagates to Health Connect (auto-prompted on first launch if outdated)

## Build

```bash
cd apps/android
./gradlew installDebug
```

For first-time setup, also run the Gradle wrapper bootstrap:

```bash
gradle wrapper --gradle-version 8.7
```

## What it does

1. On first launch — onboarding requests Health Connect read permissions for each metric.
2. User pairs with the iPhone via a 5-minute pair-code generated on this device.
3. WorkManager periodic worker runs every 15 minutes (system-enforced minimum), pulls new samples from Health Connect since the last cursor, maps to canonical schema, and POSTs to the backend.
4. Retries with exponential backoff handled by WorkManager (`OneTimeWorkRequest` fall-back on network failures).
