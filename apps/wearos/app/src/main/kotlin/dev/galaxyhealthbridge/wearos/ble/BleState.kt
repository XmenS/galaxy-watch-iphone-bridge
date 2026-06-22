package dev.galaxyhealthbridge.wearos.ble

import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Hot state shared between the sync service and the watch UI. UI is read-only;
 * the service writes here as advertising, sensors, and BLE callbacks fire.
 */
object BleState {
    /** Human-readable status string used as the primary line in the UI. */
    val status = MutableStateFlow("Idle")

    /** Steps accumulated since the service started (resets on stop/start). */
    val stepsThisSession = MutableStateFlow(0L)

    /** Last heart rate sample we observed from Health Services. */
    val lastHrBpm = MutableStateFlow<Int?>(null)

    /** Soft warning shown under the status line (e.g. "no step sensor"). */
    val sensorWarning = MutableStateFlow<String?>(null)

    /** Active calories today, kcal, from the OS daily aggregate. */
    val activeKcal = MutableStateFlow(0.0)

    /** Distance covered today, meters, from the OS daily aggregate. */
    val distanceM = MutableStateFlow(0.0)

    /** True while a central is subscribed to the STREAM characteristic. */
    val phoneConnected = MutableStateFlow(false)

    /** Total samples queued in the local store and not yet acknowledged by a phone. */
    val pendingSamples = MutableStateFlow(0)

    /** Last time we successfully streamed samples to the phone, epoch ms. */
    val lastSyncAtMs = MutableStateFlow<Long?>(null)
}
