package dev.galaxyhealthbridge.android.data.repository

import dev.galaxyhealthbridge.android.data.local.AuthStore
import dev.galaxyhealthbridge.android.data.remote.GhbApi
import dev.galaxyhealthbridge.android.data.remote.IngestBody
import dev.galaxyhealthbridge.android.health.connect.HealthConnectReader
import io.github.aakira.napier.Napier
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncRepository @Inject constructor(
    private val reader: HealthConnectReader,
    private val api: GhbApi,
    private val authStore: AuthStore,
) {
    /** Reads new samples from Health Connect, posts to backend, advances cursor. */
    suspend fun runOnce(): Outcome {
        if (!reader.granted()) return Outcome(reason = "permissions_missing")

        val since = authStore.cursor()?.let(Instant::parse) ?: Instant.now().minus(Duration.ofDays(7))
        val until = Instant.now()
        val samples = reader.readSince(since, until)
        if (samples.isEmpty()) {
            authStore.setCursor(until.toString())
            return Outcome(uploaded = 0, duplicates = 0)
        }

        // Chunk into 1k batches to stay below the 5k server limit and keep retries cheap.
        var uploaded = 0
        var duplicates = 0
        samples.chunked(1000).forEach { batch ->
            val res = api.ingest(IngestBody(source = "samsung-health", samples = batch))
            uploaded += res.accepted
            duplicates += res.duplicates
            Napier.i("sync.batch accepted=${res.accepted} dupes=${res.duplicates}")
        }
        authStore.setCursor(until.toString())
        return Outcome(uploaded = uploaded, duplicates = duplicates)
    }

    data class Outcome(
        val uploaded: Int = 0,
        val duplicates: Int = 0,
        val reason: String? = null,
    )
}
