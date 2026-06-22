# End-to-end test: Galaxy Watch → iPhone → Apple Health

This walks you through the actual round-trip test once both apps are installed. If you haven't installed them yet, start with [`INSTALL_WEAROS.md`](INSTALL_WEAROS.md) and [`INSTALL_IOS.md`](INSTALL_IOS.md) first.

The unit-test layout (BLE protocol parser tests on the watch, sample-mapping
tests on the iPhone) is described in `README.md` under *Running the tests*.

## Prerequisites checklist

Before you start, confirm all of these:

- [ ] HealthBridge is installed on the **Galaxy Watch** and you've granted Body Sensors + Bluetooth + Activity + Notifications permissions.
- [ ] HealthBridge is installed on the **iPhone** and you've granted Bluetooth and Health permissions.
- [ ] Bluetooth is **on** on both the watch and the iPhone.
- [ ] Both devices are within ~5 m of each other for the test.
- [ ] You've worn the watch for at least ~10 minutes since launching the app, so Wear Health Services has something to send. (If you just installed it 30 seconds ago, the watch has no new samples to share yet.)

## Test 1 — Watch is advertising

1. On the watch, open **HealthBridge**.
2. Tap **Start sync**.
3. The screen should show **"Waiting for iPhone…"**.
4. A persistent notification appears at the top of the watch face showing "Sync running."

If you don't see this, jump to Troubleshooting → "Watch never shows 'Waiting for iPhone'".

## Test 2 — iPhone discovers and connects

1. On the iPhone, open **Galaxy Health Bridge**.
2. Tap **Sync via Bluetooth**.
3. Watch the **Status** field at the top of the screen. It should walk through, in order:
   - `Scanning for watch…`  (1-5 seconds)
   - `Connecting to <something>…`  (1-3 seconds)
   - `Syncing samples…`  (variable, depends on how much data)
   - `Wrote N so far…`  (counter incrementing)
   - `Done. N samples received.`

If it stalls on "Scanning…" for 15+ seconds, you'll see "Couldn't find the watch." See Troubleshooting.

## Test 3 — Data lands in Apple Health

1. Open the **Health** app on the iPhone (the white app with the heart icon, pre-installed).
2. Tap **Browse** at the bottom.
3. Tap **Heart**, then **Heart Rate**.
4. Scroll down to **Show All Data**.
5. You should see entries with **Source: Galaxy Health Bridge**, timestamped from when you wore the watch.

Repeat for **Activity → Steps** to verify step samples.

If you see "No data" or no entries from Galaxy Health Bridge, see Troubleshooting → "Sync completes but no data in Apple Health".

## Test 4 — Incremental sync (idempotency)

1. Right after a successful sync, tap **Sync via Bluetooth** on the iPhone again.
2. This time you should see **"Done. 0 samples received."** within ~2 seconds.

This confirms the cursor mechanism is working — the watch knows you already have everything up to the last sync's newest sample, so it sends nothing.

3. Wear the watch for another 5 minutes, then sync again.
4. You should see a small number of new samples this time (heart rate ticks while you wore it).

## Test 5 — Sync after watch restart

1. Restart the Galaxy Watch (long-press the power button → Restart).
2. After it boots up, **don't** open HealthBridge manually — the BootReceiver should have started the service automatically.
3. Open Galaxy Health Bridge on the iPhone, tap **Sync via Bluetooth**.
4. It should still find the watch and complete the sync. (If not, this is a known limitation — the BootReceiver works on most watches but some Wear OS variants delay broadcast receivers until the user manually launches an app.)

---

## Troubleshooting

### "Watch never shows 'Waiting for iPhone'"
- Did you tap **Start sync** on the watch?
- Did you grant Bluetooth permission when prompted? Check **watch Settings → Apps → HealthBridge → Permissions**.
- Is Bluetooth on at the watch system level? Swipe down from the watch face → check the Bluetooth tile.

### "Couldn't find the watch" on iPhone
- The watch must currently show **"Waiting for iPhone…"** for it to be discoverable. If the watch shows "Idle", tap Start again.
- iPhone Bluetooth is off. Swipe down from top-right → check the Bluetooth icon.
- The two devices are too far apart. Bring them within arm's reach for the first pairing test.
- iOS has a stale BLE scan cache. Open iPhone Settings → Bluetooth → toggle off, wait 5 seconds, toggle on. Try sync again.

### "Watch disconnected before sync finished"
- The watch's screen turned off and Wear OS aggressively suspended the BLE advertiser. Tap the watch to wake it, then retry.
- The phone moved too far during sync. Repeat closer together.

### Sync completes but no data in Apple Health
- **Most likely cause:** the watch hasn't recorded any new samples since you installed the app. Heart rate, steps, etc. need you to actually wear the watch with the sensors against your skin for several minutes. The Apple Health "No data" entry for today usually means just that.
- Confirm by checking the **Last written** field on the iPhone app — if it shows 0, no samples were sent.
- Open **Settings → Health → Data Access & Devices → Galaxy Health Bridge** on the iPhone and confirm all the toggles you want are **on**. If you accidentally tapped Don't Allow during HealthKit setup, you'll see it here.

### "Wrote N so far…" never advances past 0
- HealthKit rejected the writes. Common reason: you denied access to one or more categories. Re-grant via **Settings → Health → Data Access & Devices → Galaxy Health Bridge**.
- Check the iPhone console for log messages tagged `dev.galaxyhealthbridge.ble.sync` if you're running attached to Xcode.

### App expired on iPhone ("Unable to verify app")
- Your free Apple ID 7-day signature ran out. See the "7-day refresh problem" section of [`INSTALL_IOS.md`](INSTALL_IOS.md).

### App got killed in the background on the watch
- Wear OS battery saver killed the foreground service. Open watch **Settings → Apps → HealthBridge → Battery → Unrestricted**.

---

## What this test does NOT cover

- **Background sync** from the iPhone — currently you have to foreground the app and tap Sync. iOS-side background BLE sync is on the roadmap (see [`ROADMAP.md`](ROADMAP.md)).
- **Sleep stages, SpO₂, workouts** — not wired through yet; tracker issue: see [`ROADMAP.md`](ROADMAP.md).
- **Multiple iPhones / multiple watches** — untested, expect undefined behavior.

If you find a reproducible bug, please open an issue with: phone model + iOS version, watch model + Wear OS version, the steps you took, and the **Status** + **Error** text from the iPhone app.
