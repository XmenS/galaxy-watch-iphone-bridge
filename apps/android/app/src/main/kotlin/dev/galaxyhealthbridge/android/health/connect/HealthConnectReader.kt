package dev.galaxyhealthbridge.android.health.connect

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import dev.galaxyhealthbridge.android.domain.model.CanonicalSample
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HealthConnectReader @Inject constructor(
    private val client: HealthConnectClient,
) {
    /** The full set of permissions we ever ask for. */
    val requiredPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
    )

    suspend fun granted(): Boolean =
        client.permissionController.getGrantedPermissions().containsAll(requiredPermissions)

    /** Pull samples since `since`. Returns canonical samples ready to POST. */
    suspend fun readSince(since: Instant, until: Instant = Instant.now()): List<CanonicalSample> {
        val range = TimeRangeFilter.between(since, until)
        val out = mutableListOf<CanonicalSample>()

        out += client.readRecords(ReadRecordsRequest(StepsRecord::class, range)).records.map { r ->
            CanonicalSample(
                clientUid = uid(r.metadata.id),
                source = "samsung-health",
                type = "steps",
                unit = "count",
                value = r.count.toDouble(),
                startedAt = r.startTime.toString(),
                endedAt = r.endTime.toString(),
                metadata = mapOf("hc_id" to r.metadata.id),
            )
        }

        out += client.readRecords(ReadRecordsRequest(HeartRateRecord::class, range)).records
            .flatMap { rec ->
                rec.samples.map { s ->
                    CanonicalSample(
                        clientUid = uid("${rec.metadata.id}-${s.time.toEpochMilli()}"),
                        source = "samsung-health",
                        type = "heart_rate",
                        unit = "bpm",
                        value = s.beatsPerMinute.toDouble(),
                        startedAt = s.time.toString(),
                        endedAt = s.time.toString(),
                        metadata = mapOf("hc_id" to rec.metadata.id),
                    )
                }
            }

        out += client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, range)).records
            .flatMap { rec ->
                rec.stages.map { stage ->
                    val type = when (stage.stage) {
                        SleepSessionRecord.STAGE_TYPE_AWAKE -> "sleep_awake"
                        SleepSessionRecord.STAGE_TYPE_LIGHT -> "sleep_light"
                        SleepSessionRecord.STAGE_TYPE_DEEP  -> "sleep_deep"
                        SleepSessionRecord.STAGE_TYPE_REM   -> "sleep_rem"
                        else -> "sleep_in_bed"
                    }
                    CanonicalSample(
                        clientUid = uid("${rec.metadata.id}-${stage.startTime.toEpochMilli()}"),
                        source = "samsung-health",
                        type = type,
                        startedAt = stage.startTime.toString(),
                        endedAt = stage.endTime.toString(),
                        metadata = mapOf("hc_id" to rec.metadata.id),
                    )
                }
            }

        out += client.readRecords(ReadRecordsRequest(OxygenSaturationRecord::class, range)).records.map { r ->
            CanonicalSample(
                clientUid = uid(r.metadata.id),
                source = "samsung-health",
                type = "spo2",
                unit = "%",
                value = r.percentage.value,
                startedAt = r.time.toString(),
                endedAt = r.time.toString(),
                metadata = mapOf("hc_id" to r.metadata.id),
            )
        }

        out += client.readRecords(ReadRecordsRequest(TotalCaloriesBurnedRecord::class, range)).records.map { r ->
            CanonicalSample(
                clientUid = uid(r.metadata.id),
                source = "samsung-health",
                type = "active_energy",
                unit = "kcal",
                value = r.energy.inKilocalories,
                startedAt = r.startTime.toString(),
                endedAt = r.endTime.toString(),
                metadata = mapOf("hc_id" to r.metadata.id),
            )
        }

        return out
    }

    private fun uid(stable: String): String =
        UUID.nameUUIDFromBytes(stable.toByteArray()).toString()
}
