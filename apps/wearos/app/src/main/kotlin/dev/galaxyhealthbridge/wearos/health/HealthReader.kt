package dev.galaxyhealthbridge.wearos.health

import android.content.Context
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.util.Log
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.MeasureClient
import androidx.health.services.client.PassiveListenerCallback
import androidx.health.services.client.PassiveMonitoringClient
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import androidx.health.services.client.data.IntervalDataPoint
import androidx.health.services.client.data.PassiveListenerConfig
import androidx.health.services.client.data.SampleDataPoint
import dev.galaxyhealthbridge.wearos.ble.BleState
import dev.galaxyhealthbridge.wearos.data.SampleStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.UUID

/**
 * Pulls health data off the watch into [SampleStore] + [BleState].
 *
 * Three independent pipelines:
 *  1. **Hardware step counter** for sub-second step deltas (UI).
 *  2. **MeasureClient** for live HR (samples every ~1s while subscribed).
 *  3. **PassiveListener on DAILY_* aggregates** for cumulative steps / calories /
 *     distance / floors. On Galaxy Watch 4 these update far more reliably than the
 *     per-event CALORIES/DISTANCE delta streams (which only fire when Samsung
 *     Health is actively tracking). We diff against the last reported value to
 *     emit deltas the iPhone can write to HealthKit without double-counting.
 */
class HealthReader(
    private val ctx: Context,
    private val store: SampleStore,
    private val scope: CoroutineScope,
) {
    private val client: PassiveMonitoringClient = HealthServices.getClient(ctx).passiveMonitoringClient
    private val measureClient: MeasureClient = HealthServices.getClient(ctx).measureClient
    private val sensorManager: SensorManager =
        ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val stepCounterSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    private val stepDetectorSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

    /**
     * The daily aggregates publish a running total since midnight. Subscribing here
     * is what makes calories / distance actually flow on Galaxy Watch 4.
     * HR stays on the per-sample stream for back-fill while MeasureClient handles
     * live values for the UI.
     */
    private val passiveTypes: Set<DeltaDataType<*, *>> = setOf(
        DataType.HEART_RATE_BPM,
        DataType.STEPS_DAILY,
        DataType.CALORIES_DAILY,
        DataType.DISTANCE_DAILY,
        DataType.FLOORS_DAILY,
    )

    private var lastStepCounter: Long = -1L
    private var lastStepReadingAtMs: Long = 0L

    private val prefs: SharedPreferences =
        ctx.getSharedPreferences("ghb.health_reader", Context.MODE_PRIVATE)

    private var flushJob: Job? = null
    private var measureSubscribed: Boolean = false

    private val stepListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val now = System.currentTimeMillis()
            val delta: Long = when (event.sensor.type) {
                Sensor.TYPE_STEP_COUNTER -> {
                    val current = event.values[0].toLong()
                    if (lastStepCounter < 0L) {
                        lastStepCounter = current
                        lastStepReadingAtMs = now
                        Log.i(TAG, "hw step counter baseline=$current")
                        return
                    }
                    val d = current - lastStepCounter
                    lastStepCounter = current
                    d
                }
                Sensor.TYPE_STEP_DETECTOR -> 1L
                else -> 0L
            }
            if (delta <= 0L) return
            lastStepReadingAtMs = now
            BleState.stepsThisSession.value += delta
            // NOTE: We do NOT write hardware step deltas to the store — DAILY_STEPS
            // from Health Services is the source of truth for what goes to HealthKit.
            // Hardware sensor only powers the watch's own live UI.
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val measureCallback = object : MeasureCallback {
        override fun onAvailabilityChanged(dataType: DeltaDataType<*, *>, availability: Availability) {
            Log.i(TAG, "HR availability=$availability")
        }

        override fun onDataReceived(data: DataPointContainer) {
            val now = System.currentTimeMillis()
            data.getData(DataType.HEART_RATE_BPM).forEach { p: SampleDataPoint<Double> ->
                val bpm = p.value.toInt()
                if (bpm > 0) {
                    BleState.lastHrBpm.value = bpm
                    val uid = uid("hr-measure", now)
                    scope.launch(Dispatchers.IO) {
                        runCatching { store.add(uid, "hr", p.value, "bpm", now, now) }
                    }
                }
            }
        }
    }

    suspend fun start() {
        val cfg = PassiveListenerConfig.builder().setDataTypes(passiveTypes).build()
        client.setPassiveListenerCallback(cfg, callback)

        val counterOk = stepCounterSensor?.let {
            sensorManager.registerListener(stepListener, it, SensorManager.SENSOR_DELAY_NORMAL)
        } ?: false
        if (!counterOk) {
            val detectorOk = stepDetectorSensor?.let {
                sensorManager.registerListener(stepListener, it, SensorManager.SENSOR_DELAY_NORMAL)
            } ?: false
            if (!detectorOk) {
                BleState.sensorWarning.value = "No step sensor available"
                Log.w(TAG, "no step sensor")
            } else {
                BleState.sensorWarning.value = null
                Log.i(TAG, "using TYPE_STEP_DETECTOR")
            }
        } else {
            BleState.sensorWarning.value = null
            Log.i(TAG, "using TYPE_STEP_COUNTER")
        }
        BleState.stepsThisSession.value = 0L

        runCatching {
            measureClient.registerMeasureCallback(DataType.HEART_RATE_BPM, measureCallback)
            measureSubscribed = true
            Log.i(TAG, "MeasureClient subscribed for HR")
        }.onFailure {
            Log.e(TAG, "MeasureClient register failed", it)
        }

        // Periodically flush passive buffers so daily aggregates reach us promptly.
        flushJob?.cancel()
        flushJob = scope.launch {
            while (isActive) {
                delay(30_000)
                runCatching { client.flushAsync().await() }
            }
        }
    }

    suspend fun stop() {
        flushJob?.cancel()
        flushJob = null
        runCatching { sensorManager.unregisterListener(stepListener) }
        runCatching { client.clearPassiveListenerCallbackAsync().await() }
        if (measureSubscribed) {
            runCatching {
                measureClient.unregisterMeasureCallbackAsync(
                    DataType.HEART_RATE_BPM, measureCallback,
                ).await()
            }
            measureSubscribed = false
        }
    }

    private val callback = object : PassiveListenerCallback {
        override fun onNewDataPointsReceived(dataPoints: DataPointContainer) {
            scope.launch(Dispatchers.IO) { runCatching { ingest(dataPoints) } }
        }
    }

    private suspend fun ingest(dp: DataPointContainer) {
        dp.getData(DataType.HEART_RATE_BPM).forEach { p: SampleDataPoint<Double> ->
            val ts = epochMillis(p.timeDurationFromBoot.toMillis())
            BleState.lastHrBpm.value = p.value.toInt()
            // HR is a per-event sample, not a daily aggregate. Unique uid per timestamp.
            store.add(uid("hr-passive", ts), "hr", p.value, "bpm", ts, ts)
        }
        dp.getData(DataType.STEPS_DAILY).forEach { p: IntervalDataPoint<Long> ->
            val total = p.value.toDouble()
            BleState.stepsThisSession.value = total.toLong()
            upsertDailyTotal("steps", "count", total)
        }
        dp.getData(DataType.CALORIES_DAILY).forEach { p: IntervalDataPoint<Double> ->
            BleState.activeKcal.value = p.value
            // Health Services defines CALORIES_DAILY as total energy (BMR + activity).
            // Never label this as active energy; HealthKit has no combined daily-energy type.
            upsertDailyTotal("cal_total", "kcal", p.value)
        }
        dp.getData(DataType.DISTANCE_DAILY).forEach { p: IntervalDataPoint<Double> ->
            BleState.distanceM.value = p.value
            upsertDailyTotal("dist", "m", p.value)
        }
        dp.getData(DataType.FLOORS_DAILY).forEach { p: IntervalDataPoint<Double> ->
            upsertDailyTotal("floors", "count", p.value)
        }
    }

    /**
     * Emit a single canonical "today's total" sample per metric per day. The
     * `clientUid` is deterministic (`<metric>-day-<dayKey>`), so multiple updates
     * to the running total all share one identity. On the iPhone we dedup by this
     * uid: an incoming sample with the same uid replaces the prior HealthKit
     * sample for that day. This means:
     *   - watch restarts no longer double-count
     *   - iPhone cursor resets re-pull the same total cleanly
     *   - drifty wall clocks on the watch don't fragment a day across timestamps
     *
     * We also stamp `startMs` ≈ now so the BLE cursor filter (`startMs > cursor`)
     * always picks up the latest version.
     */
    private suspend fun upsertDailyTotal(type: String, unit: String, total: Double) {
        if (total < 0.0) return
        val nowMs = System.currentTimeMillis()
        val sampleStart = nowMs - 60_000L
        val day = todayKey()
        val sampleUid = "$type-day-$day"
        Log.i(TAG, "upsert $type day=$day total=$total uid=$sampleUid")
        store.upsert(sampleUid, type, total, unit, sampleStart, nowMs)
    }

    private fun epochMillis(durationFromBootMs: Long): Long {
        val bootInstant = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        return bootInstant + durationFromBootMs
    }

    private fun todayKey(): Int {
        val c = Calendar.getInstance()
        return c.get(Calendar.YEAR) * 1000 + c.get(Calendar.DAY_OF_YEAR)
    }

    private fun uid(type: String, anchorMs: Long): String =
        UUID.nameUUIDFromBytes("$type-$anchorMs".toByteArray()).toString()

    companion object {
        private const val TAG = "HealthReader"
    }
}
