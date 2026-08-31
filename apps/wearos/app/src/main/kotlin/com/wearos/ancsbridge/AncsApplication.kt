package com.wearos.ancsbridge

import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import com.wearos.ancsbridge.ble.AncsConstants

class AncsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        listOf(
            NotificationChannel(CHANNEL_SERVICE, "Bridge services", NotificationManager.IMPORTANCE_LOW),
            NotificationChannel(CHANNEL_INCOMING_CALL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply { lockscreenVisibility = Notification.VISIBILITY_PUBLIC },
            NotificationChannel(CHANNEL_MESSAGES, "Messages", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(CHANNEL_EMAIL, "Email", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(CHANNEL_SOCIAL, "Social", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(CHANNEL_SCHEDULE, "Schedule", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(CHANNEL_OTHER, "Other iPhone notifications", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel("ghb.sync", "Health sync", NotificationManager.IMPORTANCE_LOW),
        ).forEach(manager::createNotificationChannel)
    }

    companion object {
        const val CHANNEL_SERVICE = "ancs_service_v7"
        const val CHANNEL_INCOMING_CALL = "ancs_incoming_call_v7"
        const val CHANNEL_MESSAGES = "ancs_messages_v7"
        const val CHANNEL_EMAIL = "ancs_email_v7"
        const val CHANNEL_SOCIAL = "ancs_social_v7"
        const val CHANNEL_SCHEDULE = "ancs_schedule_v7"
        const val CHANNEL_OTHER = "ancs_other_v7"
        fun channelForCategory(categoryId: Int): String = when (categoryId) {
            AncsConstants.CATEGORY_INCOMING_CALL -> CHANNEL_INCOMING_CALL
            AncsConstants.CATEGORY_SOCIAL -> CHANNEL_SOCIAL
            AncsConstants.CATEGORY_SCHEDULE -> CHANNEL_SCHEDULE
            AncsConstants.CATEGORY_EMAIL -> CHANNEL_EMAIL
            else -> CHANNEL_OTHER
        }
    }
}
