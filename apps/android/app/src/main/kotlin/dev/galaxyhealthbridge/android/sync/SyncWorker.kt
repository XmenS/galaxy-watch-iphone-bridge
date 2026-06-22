package dev.galaxyhealthbridge.android.sync

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import dev.galaxyhealthbridge.android.data.repository.SyncRepository
import io.github.aakira.napier.Napier

@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val repo: SyncRepository,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = try {
        val o = repo.runOnce()
        Napier.i("SyncWorker uploaded=${o.uploaded} dupes=${o.duplicates} reason=${o.reason}")
        if (o.reason == "permissions_missing") Result.success() else Result.success()
    } catch (e: Throwable) {
        Napier.w("SyncWorker failed: ${e.message}", e)
        if (runAttemptCount < 5) Result.retry() else Result.failure()
    }
}
