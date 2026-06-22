package dev.galaxyhealthbridge.android

import com.google.common.truth.Truth.assertThat
import dev.galaxyhealthbridge.android.domain.model.CanonicalSample
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class CanonicalSampleTest {

    private val json = Json { explicitNulls = false }

    @Test
    fun serializesUnderscoreKeys() {
        val s = CanonicalSample(
            clientUid = "uid-1",
            source = "samsung-health",
            type = "heart_rate",
            unit = "bpm",
            value = 72.0,
            startedAt = "2026-01-01T00:00:00Z",
            endedAt = "2026-01-01T00:00:01Z",
        )
        val out = json.encodeToString(s)
        assertThat(out).contains("\"client_uid\":\"uid-1\"")
        assertThat(out).contains("\"started_at\":\"2026-01-01T00:00:00Z\"")
    }
}
