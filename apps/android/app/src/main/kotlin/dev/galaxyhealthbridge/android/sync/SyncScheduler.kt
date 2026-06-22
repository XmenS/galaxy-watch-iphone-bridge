package dev.galaxyhealthbridge.android.sync

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Duration
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncScheduler @Inject constructor(
    @ApplicationContext private val ctx: Context,
) {
    fun schedulePeriodic() {
        val req = PeriodicWorkRequestBuilder<SyncWorker>(
            Duration.ofMinutes(15)              // system-enforced minimum
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
            "ghb.sync.periodic",
            ExistingPeriodicWorkPolicy.UPDATE,
            req,
        )
    }

    fun triggerOnce() {
        WorkManager.getInstance(ctx).enqueueUniqueWork(
            "ghb.sync.oneshot",
            androidx.work.ExistingWorkPolicy.REPLACE,
            androidx.work.OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
                )
                .build()
        )
    }
}
