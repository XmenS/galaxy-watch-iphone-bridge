package dev.galaxyhealthbridge.wearos.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * On device boot, automatically (re)start the SyncService so the user doesn't have to
 * relaunch the watch app every time the watch reboots. The user can still stop sync
 * from the UI; this only restores it after a power cycle.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        ContextCompat.startForegroundService(
            context,
            Intent(context, SyncService::class.java).setAction(SyncService.ACTION_START),
        )
    }
}
