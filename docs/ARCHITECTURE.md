# Architecture

The project is two apps that talk over Bluetooth LE. There is no server, no
account system, no cloud component.

```
 Galaxy Watch (Wear OS app)              iPhone (iOS app)
 ┌────────────────────────────┐          ┌────────────────────────────┐
 │ HealthReader               │          │ BLESyncView (UI)           │
 │   ↓                        │          │   ↓                        │
 │ Wear Health Services       │          │ BLESyncCoordinator         │
 │   (passive + measure)      │          │   ↓                        │
 │   ↓                        │          │ BLEClient (CoreBluetooth)  │
 │ SampleStore (Room DB)      │   BLE    │   ↓                        │
 │   ↓                        │ ───────► │ HealthKitManager           │
 │ GattServer (BLE peripheral)│          │   ↓                        │
 └────────────────────────────┘          │ HealthKit                  │
                                         └────────────────────────────┘
```

The watch is the BLE peripheral, the iPhone is the central. The wire contract
is small and lives in two files that mirror each other:

* Watch: `apps/wearos/app/src/main/kotlin/dev/galaxyhealthbridge/wearos/ble/Protocol.kt`
* iPhone: `apps/ios/GalaxyHealthBridge/Services/BLEClient.swift`

## BLE service

```
Service        e2a00001-1234-5678-9abc-def012345678
  REQUEST char e2a00002-...  write-without-response  (8 bytes LE: cursor in ms)
  STREAM  char e2a00003-...  notify                  (JSON frame chunks)
  STATUS  char e2a00004-...  read + notify           (JSON status payload)
```

* **REQUEST**: the iPhone writes the 8-byte millisecond cursor it last
  successfully ingested. A sentinel value tells the watch to reset its local
  sample buffer before streaming.
* **STREAM**: the watch sends JSON frames of type `data` (a batch of samples)
  followed by exactly one `done` frame (`{ newest_ms, total }`).
* **STATUS**: a quick read used by the iPhone UI to show the newest sample
  timestamp and the pending count without forcing a full sync.

## Sample model

Both sides agree on a small canonical record:

| field        | type    | notes                                                          |
|--------------|---------|----------------------------------------------------------------|
| `client_uid` | string  | UUID picked by the watch. Used as the HealthKit dedupe key.    |
| `type`       | string  | One of `heart_rate`, `steps`, `distance`, `active_energy`, `flights_climbed`. |
| `unit`       | string? | Matches the HealthKit unit for that type.                      |
| `value`      | number? | The reading. Numeric types only.                               |
| `started_at` | int64   | Sample start, ms since epoch (watch clock).                    |
| `ended_at`   | int64   | Sample end, ms since epoch.                                    |
| `metadata`   | object? | Free-form context (e.g. measurement context for heart rate).    |

Sample types currently wired end-to-end are listed in the README. The iOS
`CanonicalSampleType` enum lists more cases so the mapping layer is ready when
new metric streams are added, but the watch only emits the types above.

## Sync flow

1. The watch's `SyncService` (a foreground service) starts `HealthReader` and
   `GattServer`. The reader subscribes to `PassiveMonitoringClient` for steps /
   calories / distance / floors, and to `MeasureClient` for live heart rate.
2. As samples arrive, the reader writes them into Room (`SampleStore`).
3. The iPhone scans for the service UUID, connects, and writes its cursor on
   the REQUEST characteristic.
4. The watch reads `SampleStore` rows newer than the cursor, splits them into
   frames sized to fit the negotiated MTU, and pushes them on STREAM.
5. The iPhone collects each frame, decodes to `CanonicalSample`, rebases
   timestamps if the watch clock is obviously wrong (see `rebaseTimestamps` in
   `BLESyncCoordinator`), maps to `HKSample`, and writes via `HKHealthStore`.
6. After the watch sends `done`, the iPhone stores the newest timestamp it saw
   as the cursor so the next sync skips everything it already has.

## Time rebasing

If the watch reports a sample with `ended_at` more than a few weeks away from
the iPhone's current time, the iPhone treats the watch clock as wrong, rebases
`ended_at` to `now`, and preserves the original `ended_at − started_at`
duration. This is covered by
`BLESyncCoordinatorTests.testRebaseRewritesTimestampsWhenWatchClockIsWildlyOff`.

## Dedupe

The iPhone passes `client_uid` into `HKMetadataKeyExternalUUID` so HealthKit's
own dedupe drops a sample that has already been written. Re-running a sync is
safe.

## Storage

* Watch: a single-table Room DB at `apps/wearos/app/src/main/kotlin/.../data/SampleStore.kt`.
* iPhone: a `cursor` value plus an install ID in `UserDefaults`
  (`apps/ios/GalaxyHealthBridge/Storage/LocalStore.swift`). HealthKit owns the
  actual sample storage.

## What is not in this repo

There is no backend service, no message queue, no relational database, no
Docker stack, no Terraform, and no account system. The project is intentionally
limited to the BLE pipeline above. The iPhone needs to be unlocked with the
app foregrounded for a sync to run; background sync over BLE is a roadmap item,
not a shipped feature.
