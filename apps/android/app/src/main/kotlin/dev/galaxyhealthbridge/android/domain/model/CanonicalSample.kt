package dev.galaxyhealthbridge.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Mirrors the FastAPI canonical types. Keep in sync with services/api/app/schemas/health.py. */
enum class CanonicalType(val wire: String) {
    STEPS("steps"),
    DISTANCE("distance"),
    ACTIVE_ENERGY("active_energy"),
    BASAL_ENERGY("basal_energy"),
    HEART_RATE("heart_rate"),
    RESTING_HEART_RATE("resting_heart_rate"),
    HRV("hrv"),
    SPO2("spo2"),
    RESPIRATORY_RATE("respiratory_rate"),
    BODY_TEMPERATURE("body_temperature"),
    BLOOD_PRESSURE_SYSTOLIC("blood_pressure_systolic"),
    BLOOD_PRESSURE_DIASTOLIC("blood_pressure_diastolic"),
    BODY_MASS("body_mass"),
    BODY_FAT_PERCENTAGE("body_fat_percentage"),
    LEAN_BODY_MASS("lean_body_mass"),
    SLEEP_IN_BED("sleep_in_bed"),
    SLEEP_AWAKE("sleep_awake"),
    SLEEP_LIGHT("sleep_light"),
    SLEEP_DEEP("sleep_deep"),
    SLEEP_REM("sleep_rem"),
    WORKOUT("workout"),
    MINDFUL_MINUTES("mindful_minutes"),
    STAND_HOURS("stand_hours"),
    VO2_MAX("vo2_max"),
    STRESS_SCORE("stress_score");
}

@Serializable
data class CanonicalSample(
    @SerialName("client_uid") val clientUid: String,
    val source: String,
    val type: String,
    val unit: String? = null,
    val value: Double? = null,
    @SerialName("started_at") val startedAt: String,    // ISO-8601
    @SerialName("ended_at") val endedAt: String,
    val metadata: Map<String, String> = emptyMap(),
    @SerialName("nonce_b64") val nonceB64: String? = null,
    @SerialName("ciphertext_b64") val ciphertextB64: String? = null,
)
