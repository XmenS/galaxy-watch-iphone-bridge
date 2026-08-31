# Galaxy Watch 7 → iPhone: feasibility matrix

Verified against the official API documentation on 2026-08-31. “Available” means the API defines the data type; actual delivery must still be checked with the runtime capability API on the particular watch/firmware. The project never synthesizes a missing value.

| Metric | A: Wear OS Health Services | B: Health Connect | C: Samsung Health Data SDK | D: Samsung Health Sensor SDK | E / implementation status | Apple Health target |
|---|---|---|---|---|---|---|
| Steps | Yes, passive `STEPS_DAILY` | `StepsRecord` | Data store; phone Samsung Health and partner registration for distribution | No need | P0 implemented through A | `HKQuantityType.stepCount` |
| Heart rate | Yes, passive/measure | `HeartRateRecord` | Partner-controlled data store | Continuous sensor; partnership required for distribution | P0 implemented through A | `HKQuantityType.heartRate` |
| Resting heart rate | No dedicated type | `RestingHeartRateRecord` | Partner-controlled | No derived resting-HR record | Not implemented until a real provider is proven on-device | `HKQuantityType.restingHeartRate` |
| Active calories | No daily active-only type | `ActiveCaloriesBurnedRecord` | Partner-controlled | No | Not implemented; never derived from total calories | `HKQuantityType.activeEnergyBurned` |
| Total calories | `CALORIES_DAILY` (BMR + activity) | `TotalCaloriesBurnedRecord` | Partner-controlled | No | Captured locally as `cal_total`, intentionally not written because HealthKit has no combined equivalent | none; do not mislabel |
| Distance | Yes, `DISTANCE_DAILY` | `DistanceRecord` | Partner-controlled | No | P0 implemented through A | `HKQuantityType.distanceWalkingRunning` |
| Floors | Yes, `FLOORS_DAILY` | `FloorsClimbedRecord` | Partner-controlled | No | Implemented watch-side; iOS mapping is pending | `HKQuantityType.flightsClimbed` |
| Workout/session/type/duration | ExerciseClient can record an exercise started by this app; it cannot read arbitrary Samsung Health workout history | `ExerciseSessionRecord` plus associated records | Partner-controlled | No | P1, not implemented | `HKWorkout` |
| Workout calories/distance/HR | Available during an app-owned Health Services exercise if capability reports support | Associated Health Connect records | Partner-controlled | HR sensor only | P1, not implemented | `HKWorkout` + samples |
| Sleep start/end/stages | Health Services is not a general Samsung sleep-history reader | `SleepSessionRecord` with awake/light/deep/REM | Partner-controlled | No sleep classifier | P1, not implemented; existing iOS mappings alone do not imply watch availability | `HKCategoryType.sleepAnalysis` |
| SpO2 | Not a passive history stream | `OxygenSaturationRecord` | Partner-controlled | `SPO2_ON_DEMAND`, foreground measurement; partnership required for distribution | P1, not implemented | `HKQuantityType.oxygenSaturation` |
| Respiratory rate | No | `RespiratoryRateRecord` | Partner-controlled if exposed | No processed respiratory-rate tracker | P2, not implemented | `HKQuantityType.respiratoryRate` |
| VO2 max | No history reader | `Vo2MaxRecord` | Partner-controlled if exposed | No processed VO2-max tracker | P2, not implemented | `HKQuantityType.vo2Max` |
| Skin temperature | No Samsung history | `SkinTemperatureRecord` | Partner-controlled | Continuous/on-demand on supported watches; partnership required | Not implemented | Apple wrist-temperature types require careful semantic matching |

## API and distribution constraints

- Samsung Health Data SDK is primarily an Android/Samsung Health data-store integration. Public distribution requires Samsung registration of package name and signing certificate; developer mode is testing-only. It does not satisfy the no-Android-phone design by itself.
- Samsung Health Sensor SDK supports Galaxy Watch4 and later, but public distribution requires Samsung partnership. SpO2 is on-demand and must run in the foreground; it is not an API for reading Samsung Health's overnight SpO2 history.
- Health Connect defines most desired record classes, but that does not prove Samsung Health publishes those records into a Health Connect provider accessible to a standalone Wear app. The app must report provider availability and granted permissions before this path can be enabled.
- `CALORIES_DAILY` in Health Services is explicitly total calories including BMR and activity. It must not be written as HealthKit active energy.

## Notifications and media

ANCS provides notification category, app identifier, title/subtitle/message, date, and action labels. It does not provide the source application's icon; this project maps known categories to local glyphs. Incoming-call name/number is only whatever iOS exposes in the notification text. Media transport control is not implemented: iOS does not expose a public CoreBluetooth API that lets an arbitrary app publish the system AVRCP remote-control target, and no private API is used.

## Sources

- Android Health Services `DataType`: https://developer.android.com/reference/androidx/health/services/client/data/DataType
- Health Connect records: https://developer.android.com/reference/kotlin/androidx/health/connect/client/records/package-summary
- Health Connect sleep sessions: https://developer.android.com/health-and-fitness/health-connect/features/sleep-sessions
- Apple ANCS specification: https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Introduction/Introduction.html
- Samsung Health Sensor SDK: https://developer.samsung.com/health/sensor/guide/introduction.html
- Samsung Sensor SDK FAQ/partnership: https://developer.samsung.com/health/sensor/faq.html
- Samsung Health Data SDK process: https://developer.samsung.com/health/data/process.html
