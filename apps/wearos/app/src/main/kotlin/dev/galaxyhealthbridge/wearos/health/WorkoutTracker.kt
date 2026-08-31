package dev.galaxyhealthbridge.wearos.health

import android.content.Context
import android.util.Log
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import dev.galaxyhealthbridge.wearos.ble.BleState
import dev.galaxyhealthbridge.wearos.data.SampleStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.withContext
import java.util.UUID

/** Records workouts started by this app. It does not claim access to Samsung Health history. */
class WorkoutTracker(context: Context, private val store: SampleStore) {
    private val client = HealthServices.getClient(context).exerciseClient
    private var startMs = 0L
    private var distanceM: Double? = null
    private var caloriesKcal: Double? = null
    private var averageHr: Double? = null

    private val callback = object : ExerciseUpdateCallback {
        override fun onRegistered() { Log.i(TAG, "callback registered") }
        override fun onRegistrationFailed(throwable: Throwable) { Log.e(TAG, "callback failed", throwable) }
        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit
        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
            Log.i(TAG, "availability $dataType=$availability")
        }

        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val metrics = update.latestMetrics
            distanceM = metrics.getData(DataType.DISTANCE_TOTAL)?.total
            caloriesKcal = metrics.getData(DataType.CALORIES_TOTAL)?.total
            averageHr = metrics.getData(DataType.HEART_RATE_BPM_STATS)?.average
            BleState.workoutElapsedSeconds.value =
                update.activeDurationCheckpoint?.activeDuration?.seconds ?: 0L
        }
    }

    suspend fun startWalking() = withContext(Dispatchers.IO) {
        if (BleState.workoutActive.value) return@withContext
        client.setUpdateCallback(callback)
        val config = ExerciseConfig.Builder(ExerciseType.WALKING)
            .setDataTypes(setOf(DataType.DISTANCE_TOTAL, DataType.CALORIES_TOTAL, DataType.HEART_RATE_BPM_STATS))
            .setIsGpsEnabled(false)
            .setIsAutoPauseAndResumeEnabled(false)
            .build()
        client.startExerciseAsync(config).await()
        startMs = System.currentTimeMillis()
        BleState.workoutElapsedSeconds.value = 0L
        BleState.workoutActive.value = true
        Log.i(TAG, "walking started")
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        if (!BleState.workoutActive.value) return@withContext
        runCatching { client.flushAsync().await() }
        client.endExerciseAsync().await()
        val endMs = System.currentTimeMillis()
        val uid = UUID.nameUUIDFromBytes("workout-walking-$startMs".toByteArray()).toString()
        store.addWorkout(uid, startMs, endMs, "walking", distanceM, caloriesKcal, averageHr)
        runCatching { client.clearUpdateCallbackAsync(callback).await() }
        Log.i(TAG, "stored uid=$uid distance=$distanceM kcal=$caloriesKcal avgHr=$averageHr")
        startMs = 0L
        BleState.workoutActive.value = false
        BleState.workoutElapsedSeconds.value = 0L
    }

    companion object { private const val TAG = "GhbWorkout" }
}
