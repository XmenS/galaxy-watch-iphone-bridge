# Install Galaxy Health Bridge on your iPhone

This is the free-tier path: $0, no Apple Developer account needed, the iPhone app you install is literally the source you can read in this repo.

**Time estimate:** 30-60 minutes the first time (most of which is Xcode downloading). 2 minutes for subsequent re-signs.

## What you need

- A **Mac** running macOS 14 (Sonoma) or newer. If you don't own one, borrowing for an hour is enough.
- A **free Apple ID** — the same one you sign into your iPhone with works perfectly. No payment, no developer fee.
- An **iPhone** running iOS 16 or later.
- A **USB-C / Lightning cable** that fits both your Mac and your iPhone.

## Step 1 — Install Xcode on the Mac

Xcode is Apple's developer toolchain. We need it to sign the app for your iPhone.

1. Open the **Mac App Store** on the Mac.
2. Search for **Xcode**. Click **Get** / **Install**.
3. Xcode is around 15 GB. On home Wi-Fi expect 30 to 60 minutes for the download to finish.
4. When done, launch Xcode at least once and accept the license. It will install command-line tools on first launch.

Then in a Terminal:

```bash
xcode-select --install        # if it prompts, click Install. Skip if already there.
sudo xcodebuild -license accept
brew install xcodegen          # if you don't have brew: https://brew.sh
```

## Step 2 — Get the source

```bash
git clone https://github.com/<your-fork>/galaxy-health-bridge.git
cd galaxy-health-bridge/apps/ios
xcodegen generate
open GalaxyHealthBridge.xcodeproj
```

The last line opens the project in Xcode.

## Step 3 — Sign in with your Apple ID

In Xcode:

1. **Xcode menu → Settings → Accounts** (top menu bar).
2. Click the **+** in the bottom-left, choose **Apple ID**, sign in with the same Apple ID you use on your iPhone.
3. Close Settings.

## Step 4 — Configure signing for the project

In the Xcode window that opened:

1. In the left sidebar, click the blue project icon at the very top (`GalaxyHealthBridge`).
2. Pick the **GalaxyHealthBridge** target in the middle pane, then the **Signing & Capabilities** tab.
3. Check **Automatically manage signing**.
4. **Team:** select your Apple ID (it'll show as "Your Name (Personal Team)").
5. **Bundle Identifier:** change it to something unique like `dev.galaxyhealthbridge.app.<yourname>` (e.g. `...app.piyush`). Apple's free tier only allows one user per bundle ID globally.

If you see a red error about provisioning, click **Try Again** — Xcode will issue you a free 7-day development certificate.

## Step 5 — Plug in your iPhone and install

1. Connect your iPhone to the Mac with the cable. On the iPhone, tap **Trust** when it asks "Trust This Computer?".
2. At the top of the Xcode window, there's a device picker (looks like `GalaxyHealthBridge ▸ [some simulator]`). Click it and select **your iPhone** under "iOS Device".
3. Press **⌘R** (or click the ▶ play button).
4. Xcode will compile, install, and try to launch the app on your iPhone. The first build takes ~3 minutes.

The first launch on the iPhone shows: **"Untrusted Developer."** That's expected.

1. On the **iPhone**: Settings → General → **VPN & Device Management**.
2. Tap your Apple ID under "Developer App", tap **Trust**, confirm.
3. Now tap the **Galaxy Health Bridge** icon on the home screen. It opens.
4. iOS will ask for **Bluetooth** permission — tap Allow.
5. The first time you tap "Sync via Bluetooth", iOS will also ask for **Health** access — tap **Turn On All Categories**, then **Allow**.

You're installed. Now go follow [`INSTALL_WEAROS.md`](INSTALL_WEAROS.md) for the watch side, then [`TESTING.md`](TESTING.md) to verify the round trip.

---

## The 7-day refresh problem (and how to deal with it)

Free Apple ID signatures expire after **7 days**. When that happens, opening the app on your iPhone shows "Unable to verify app" and it won't launch until you re-sign.

You have two options:

### Option A — Manual refresh (easy, do it weekly)

Just open Xcode on the Mac with your iPhone plugged in and hit **⌘R** again. Done — 30 seconds. Set a calendar reminder for every Saturday.

### Option B — AltStore auto-refresh (recommended)

[AltStore](https://altstore.io/) is a free tool that keeps a small companion app running on your Mac. As long as the Mac is on the same Wi-Fi as your iPhone, it transparently re-signs your apps every 7 days, automatically. You install it once, then forget it exists.

To use it:

1. Install **AltServer** on your Mac from <https://altstore.io/>.
2. Connect your iPhone via cable; from AltServer's menu-bar icon, choose **Install AltStore → [your iPhone]**. Sign in with your Apple ID when prompted.
3. The first time, instead of pressing ⌘R in Xcode, choose **Product → Archive**, export an "iOS App" (`.ipa`).
4. In AltStore on the iPhone, tap **+**, pick your `.ipa`. AltStore installs it and tracks it for refresh.
5. Keep the Mac on the same Wi-Fi as the iPhone whenever you can. AltServer will refresh in the background.

---

## Troubleshooting

**"Could not launch — failed to register bundle identifier"**
Your bundle identifier collides with someone else's free-tier app. Change it to `dev.galaxyhealthbridge.app.<somethingelse>` in Step 4.

**"No code signing identities found"**
You didn't add your Apple ID in Step 3, or your Apple ID isn't enabled for free development. Go to Xcode Settings → Accounts, pick your Apple ID, click **Manage Certificates** → **+** → **Apple Development**.

**Build error: "module 'CoreBluetooth' not found"**
Re-run `xcodegen generate` from `apps/ios/` — the project file needs regenerating.

**App installed but immediately says "Untrusted Developer"**
You skipped Step 5's trust step. Go to **Settings → General → VPN & Device Management** on the iPhone and trust your developer profile.

**"Sync via Bluetooth" finds nothing**
Your watch isn't advertising yet. See [`INSTALL_WEAROS.md`](INSTALL_WEAROS.md) — you need to open HealthBridge on the watch and tap **Start sync** first.

**Sync starts but no samples show up in Apple Health**
The watch hasn't collected new data since the last sync. Wear it for 10 minutes, walk around, then try again. Wear Health Services batches deliveries.
