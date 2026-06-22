package dev.galaxyhealthbridge.wearos.service

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import dev.galaxyhealthbridge.wearos.R
import dev.galaxyhealthbridge.wearos.ble.GattServer
import dev.galaxyhealthbridge.wearos.data.SampleStore
import dev.galaxyhealthbridge.wearos.health.HealthReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Long-running foreground service that owns the BLE peripheral + Health Services subscription.
 * Both run for the lifetime of the service; the UI is just a switch.
 */
class SyncService : LifecycleService() {

    private lateinit var store: SampleStore
    private lateinit var reader: HealthReader
    private lateinit var gatt: GattServer
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        store = SampleStore(applicationContext)
        reader = HealthReader(applicationContext, store, lifecycleScope)
        gatt = GattServer(applicationContext, store, lifecycleScope)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_STOP -> { stopWork(); stopSelf(); return START_NOT_STICKY }
            else -> startWork()
        }
        return START_STICKY
    }

    private fun startWork() {
        acquireWakeLock()
        startForegroundCompat()
        lifecycleScope.launch(Dispatchers.IO) {
            // Prune anything older than the start of yesterday so the store can
            // never grow indefinitely. Today's idempotent total rows stay; old
            // per-event rows (HR samples, etc.) get cleaned up automatically.
            val cutoff = System.currentTimeMillis() - 36L * 60L * 60L * 1000L
            runCatching { store.pruneOlderThan(cutoff) }
            runCatching { reader.start() }
        }
        gatt.start()
    }

    private fun stopWork() {
        gatt.stop()
        lifecycleScope.launch(Dispatchers.IO) { runCatching { reader.stop() } }
        releaseWakeLock()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ghb:sync",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    private fun startForegroundCompat() {
        val tap = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n: Notification = NotificationCompat.Builder(this, "ghb.sync")
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.status_advertising))
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setContentIntent(tap)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID, n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    override fun onDestroy() {
        stopWork()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "dev.galaxyhealthbridge.wearos.action.START"
        const val ACTION_STOP = "dev.galaxyhealthbridge.wearos.action.STOP"
        private const val NOTIF_ID = 1
    }
}
