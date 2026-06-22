# Install Galaxy Health Bridge on your Galaxy Watch

The watch app side is straightforward — there is no expiry, no signing dance. Install it once and forget it.

**Time estimate:** 5-10 minutes.

## What you need

- A **Galaxy Watch 4, 5, 6, or Ultra** running Wear OS 3 or newer.
- A computer (Mac, Windows, or Linux) with **adb** installed.
- The watch needs to be on the **same Wi-Fi network** as the computer, OR connected via the Galaxy Wearable Bluetooth bridge.

## Step 1 — Get adb

**Mac:**
```bash
brew install --cask android-platform-tools
```

**Windows / Linux:** download "SDK Platform Tools" from <https://developer.android.com/tools/releases/platform-tools> and unzip. Add the folder to your `PATH` (or `cd` into it for the commands below).

Verify:
```bash
adb --version
```

## Step 2 — Enable developer mode on the watch

1. On the watch: **Settings → About watch → Software information**.
2. Tap **Software version** seven times. Keep tapping — eventually the watch will buzz and say "Developer mode turned on".
3. Go back to **Settings → Developer options** (now appears at the bottom of Settings).
4. Enable **ADB debugging**.
5. Enable **Debug over Wi-Fi**.
6. Wait a few seconds — under "Debug over Wi-Fi" the watch will show an IP and port, e.g. `192.168.1.42:5555`. Write it down.

## Step 3 — Download the APK

The easiest path: grab the latest pre-built APK from GitHub Releases.

1. Go to **<https://github.com/\<your-fork\>/galaxy-health-bridge/releases/latest>**.
2. Download `wearos-app-debug.apk` to your computer.

**Or, build from source** if you'd rather audit the binary you install:

```bash
cd apps/wearos
./gradlew :app:assembleDebug
# APK lands at app/build/outputs/apk/debug/app-debug.apk
```

You'll need a JDK 17 and Android command-line tools for this (Android Studio bundles both).

## Step 4 — Push the APK to the watch

```bash
adb connect 192.168.1.42:5555      # use the IP from Step 2
```

The watch will pop up an **"Allow USB debugging?"** dialog. Tap **Always allow from this computer**, then **OK**. You may need to scroll/swipe — the OK button is at the bottom of the watch.

Then:

```bash
adb -s 192.168.1.42:5555 install -r path/to/wearos-app-debug.apk
```

You should see `Success`. The HealthBridge app icon now appears in the watch's app list.

## Step 5 — Launch and grant permissions

1. On the watch, open the app launcher and tap **HealthBridge**.
2. The app will request:
   - **Body sensors** — for heart rate
   - **Physical activity** — for steps / calories / distance
   - **Bluetooth** — to advertise to the iPhone
   - **Notifications** — for the persistent "syncing" status
   - Tap **Allow** on each.
3. Tap **Start sync**.
4. The screen should now show "Waiting for iPhone…". This means the watch is BLE-advertising and ready to be paired.

The watch will keep advertising even when the screen turns off, thanks to the foreground service. The service automatically restarts after reboot, so you only do this once.

You're done on the watch side. Continue with [`TESTING.md`](TESTING.md) to actually verify data flows into Apple Health.

---

## Troubleshooting

**`adb connect` says "failed to connect"**
Watch isn't on the same network as your computer, or "Debug over Wi-Fi" got turned off. Re-check Step 2. Some routers block device-to-device traffic ("AP isolation") — try connecting both to a phone hotspot as a quick test.

**Watch never shows the "Allow USB debugging" prompt**
Scroll up on the watch face — sometimes the prompt is hidden behind the time or another notification.

**`adb install` says "INSTALL_FAILED_USER_RESTRICTED"**
You didn't tap "Always allow" in the debug prompt. Run `adb disconnect`, then `adb connect <ip>` again and watch for the prompt.

**Watch says "App not optimized for this device"**
Wear OS shows this warning for any sideloaded watch app. It's safe to dismiss — the app is built for `minSdk = 30` (Wear OS 3) and targets the current SDK.

**App shows "Waiting for iPhone…" but iPhone can't find it**
The watch needs Bluetooth turned on (separate toggle from Wi-Fi). Also confirm the iPhone has Bluetooth permission granted for Galaxy Health Bridge — see [`INSTALL_IOS.md`](INSTALL_IOS.md).

**App is silently killed after a while**
Wear OS is aggressive about killing background apps. Settings → Apps → HealthBridge → Battery → set to **Unrestricted**.
