# Galaxy Health Bridge — iPhone Companion

Native Swift app. Pulls samples from the backend and writes them to HealthKit on-device.

## Generate the Xcode project

We use [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition lives in `project.yml` (reviewable, mergeable). Run once:

```bash
brew install xcodegen
cd apps/ios
xcodegen
open GalaxyHealthBridge.xcodeproj
```

Or open `Package.swift` in Xcode to work on the core libraries in isolation (no UI).

## Requirements

- macOS 14+
- Xcode 15.4+
- iOS deployment target: 16.0
- Paid Apple Developer account (HealthKit requires a real device + signing)

## What it does

1. On first launch — onboarding requests HealthKit write permissions per metric.
2. User enters a pair-code generated on the Android app to link this iPhone to the account.
3. Every time `BGAppRefreshTask` fires (~hourly), the app fetches samples from the API, decrypts (if E2E), maps to `HKQuantitySample`/`HKCategorySample`, and writes to HealthKit.
4. Anchor cursor stored in `HKAnchoredObjectQuery`-style local state to avoid double-writes if the API replays.
