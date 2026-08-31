# Build, install, and pair

## Watch APK

From Windows PowerShell:

```powershell
cd apps\wearos
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug
adb connect WATCH_IP:5555
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

Open **Galaxy Health Bridge** on the watch, grant Activity, Sensors, Nearby devices, and Notifications, then tap Start. The same foreground start launches health sync and the ANCS consumer.

## iPhone app

On macOS with current Xcode and XcodeGen:

```bash
cd apps/ios
brew install xcodegen
xcodegen generate
open GalaxyHealthBridge.xcodeproj
```

Select your development team, connect the iPhone, select it as the run destination, then Build & Run. Grant Bluetooth and every selected Health category. A free Apple ID normally requires re-signing after seven days.

## Pairing sequence

1. Keep the iOS app in the foreground for first pairing. Its companion BLE service advertises automatically.
2. Start the bridge on the watch. The watch scans for the iPhone companion service, connects, and asks Android to create an encrypted BLE bond.
3. Accept the Bluetooth pairing prompts on both devices. ANCS characteristics only become visible after authorization/bonding.
4. Leave notification previews enabled for the content you want the accessory to receive. iOS remains the authority and may redact content according to its notification/privacy settings.
5. In the iOS app tap **Sync Now**. Health sync uses the opposite BLE roles: watch peripheral, iPhone central. The two profiles can coexist.

## Diagnostics

- Watch: `adb logcat -s HealthReader GattServer BleConnectionManager AncsService`
- iPhone: Xcode Console, filter for subsystem `dev.galaxyhealthbridge` or `com.wearos.ancsbridge`.
- A successful health transfer logs cursor write, received batches, per-batch HealthKit save results, and the final cursor.
- A successful ANCS session logs bonding, service discovery, subscriptions to Data Source then Notification Source, and parsed notification attributes.

## Security and privacy

No server or Internet endpoint exists. Health payloads remain on the two devices. ANCS requires an encrypted, authorized BLE relationship. The custom health GATT service currently relies on the OS BLE link and application UUID; first-pair identity pinning and an application-level authenticated handshake remain required before treating it as hardened against a nearby active attacker.
