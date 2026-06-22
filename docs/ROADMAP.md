# Roadmap

This roadmap lists what is missing relative to the README's promised feature
set. Items are ordered by how often they have been asked for, not by ease of
implementation. Nothing here is a commitment to a delivery date.

## Shipping today (v0.1.0)

* Steps, active calories, distance, heart rate (live + historical), floors
  climbed.
* Foreground BLE sync triggered from the iPhone.
* Manual reset of the watch's local buffer from the iPhone Settings tab.

## Planned

### Sleep stages
The Wear OS Health Services API exposes sleep stages on Wear OS 4+. Mapping is
straightforward (`asleep_in_bed`, `asleep_light`, `asleep_deep`, `asleep_rem`)
because HealthKit has matching category values. The watch needs to be worn
overnight without removing it, which most users do not do today, so we want to
ship sleep alongside a clear "wear-time" status indicator.

### SpO₂
Currently exposed by `MeasureClient` only during a foreground workout on most
Galaxy Watch models. We need to confirm whether passive overnight readings are
available in the Health Services SDK without a one-off measurement prompt.

### Workouts (HKWorkout)
The watch records workouts in Samsung Health. Health Services exposes summary
records that map onto `HKWorkout`. The blocker is matching Samsung's activity
type list to `HKWorkoutActivityType` cleanly enough that the values in Apple
Health do not look wrong.

### Background sync on iOS
Apple's `bluetooth-central` background mode wakes the app for a connected
peripheral, but the Galaxy Watch as a peripheral disconnects when its screen
goes off. The likely path is a state-restoration based reconnect plus a
foreground "tap to sync" fallback. Until this lands, the user must open the app
to sync.

### Watch APK in releases
The release workflow already attaches `wearos-app-debug.apk`. A signed release
APK would let people install without `adb` once Wear OS supports user-driven
sideloading more cleanly, or via the Play Store internal track.

## Not planned

* A cloud backend, account system, or hosted service.
* An Android phone app. The Wear OS app talks directly to the iPhone.
* Reading data from Samsung Health on a phone. We read from Health Services on
  the watch instead so a phone is not needed.
