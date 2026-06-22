package dev.galaxyhealthbridge.wearos.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class WearApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                "ghb.sync", "Sync",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Health sync to iPhone" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}
