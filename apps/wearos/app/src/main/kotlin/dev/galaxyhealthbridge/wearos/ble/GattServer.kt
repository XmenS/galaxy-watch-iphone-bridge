package dev.galaxyhealthbridge.wearos.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import dev.galaxyhealthbridge.wearos.data.SampleStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Tiny BLE GATT peripheral that exposes the GHB service so the iPhone can pull samples.
 *
 * Flow per connection:
 *   - iPhone subscribes to STREAM notify (writes CCCD).
 *   - iPhone writes 8-byte LE timestamp (cursor) to REQUEST.
 *   - We page samples from SampleStore where startMs > cursor, JSON-encode chunks
 *     no larger than MTU - 3 bytes, send each chunk as a notification on STREAM.
 *   - When done, send a Frame.Done with the newest timestamp + total count.
 *   - iPhone stores that as its next cursor.
 */
@SuppressLint("MissingPermission")
class GattServer(
    private val ctx: Context,
    private val store: SampleStore,
    private val scope: CoroutineScope,
) {
    private val json = Json { encodeDefaults = true; classDiscriminator = "kind" }
    private val mgr = ctx.getSystemService(BluetoothManager::class.java)
    private val adapter = mgr.adapter
    private val advertiser: BluetoothLeAdvertiser? get() = adapter?.bluetoothLeAdvertiser

    private var server: BluetoothGattServer? = null
    private var streamChar: BluetoothGattCharacteristic? = null
    private var statusChar: BluetoothGattCharacteristic? = null

    @Volatile private var mtu: Int = 23     // BLE default; gets negotiated higher
    @Volatile private var subscriber: BluetoothDevice? = null

    fun start() {
        if (!hasBle()) {
            Log.w(TAG, "no BLE on this device")
            BleState.status.value = "ERR: BT off/unavail"
            return
        }
        val svc = buildService()
        server = mgr.openGattServer(ctx, callback).also { it.addService(svc) }
        if (advertiser == null) {
            BleState.status.value = "ERR: no advertiser"
            return
        }
        BleState.status.value = "Starting…"
        startAdvertising()
        scope.launch(Dispatchers.IO) { refreshStatus() }
    }

    fun stop() {
        runCatching { advertiser?.stopAdvertising(adCallback) }
        runCatching { server?.close() }
        server = null
        subscriber = null
        BleState.status.value = "Idle"
    }

    private fun hasBle(): Boolean = adapter != null && adapter.isEnabled

    private fun buildService(): BluetoothGattService {
        val svc = BluetoothGattService(Protocol.SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val request = BluetoothGattCharacteristic(
            Protocol.REQUEST_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )

        val stream = BluetoothGattCharacteristic(
            Protocol.STREAM_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        ).apply {
            addDescriptor(BluetoothGattDescriptor(Protocol.CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE))
        }

        val status = BluetoothGattCharacteristic(
            Protocol.STATUS_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        ).apply {
            addDescriptor(BluetoothGattDescriptor(Protocol.CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE))
        }

        svc.addCharacteristic(request)
        svc.addCharacteristic(stream)
        svc.addCharacteristic(status)
        streamChar = stream
        statusChar = status
        return svc
    }

    private val adCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.i(TAG, "advertising started")
            BleState.status.value = "Waiting for iPhone…"
        }
        override fun onStartFailure(errorCode: Int) {
            Log.w(TAG, "advertise failed code=$errorCode")
            val why = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "data too large"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "too many advertisers"
                ADVERTISE_FAILED_ALREADY_STARTED -> "already started"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "internal error"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "BLE peripheral unsupported"
                else -> "code=$errorCode"
            }
            BleState.status.value = "ERR adv: $why"
        }
    }

    private fun startAdvertising() {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(Protocol.SERVICE_UUID))
            .build()
        advertiser?.startAdvertising(settings, data, adCallback)
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            Log.i(TAG, "conn state device=${device.address} status=$status state=$newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                BleState.status.value = "Connected ${device.address}"
                BleState.phoneConnected.value = true
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (subscriber == device) subscriber = null
                BleState.status.value = "Waiting for iPhone…"
                BleState.phoneConnected.value = false
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            this@GattServer.mtu = mtu
            Log.i(TAG, "mtu=$mtu")
            BleState.status.value = "Connected mtu=$mtu"
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray,
        ) {
            if (descriptor.uuid == Protocol.CCCD_UUID &&
                descriptor.characteristic.uuid == Protocol.STREAM_UUID) {
                val subscribing = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                subscriber = if (subscribing) device else null
                Log.i(TAG, "subscriber set=$subscribing")
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == Protocol.STATUS_UUID) {
                scope.launch(Dispatchers.IO) {
                    val payload = currentStatusJson()
                    server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, payload)
                }
            } else {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray,
        ) {
            if (characteristic.uuid == Protocol.REQUEST_UUID) {
                val payload = RequestPayload.parse(value)
                Log.i(TAG, "REQUEST write received cursor=${payload.cursorMs} reset=${payload.reset} bytes=${value.size}")
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                scope.launch(Dispatchers.IO) {
                    if (payload.reset) {
                        runCatching { store.clear() }
                        Log.i(TAG, "store cleared on iPhone reset request")
                    }
                    stream(device, payload.cursorMs)
                }
            } else if (responseNeeded) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
            }
        }
    }

    private suspend fun stream(device: BluetoothDevice, sinceMs: Long) {
        BleState.status.value = "Streaming…"
        Log.i(TAG, "stream() begin sinceMs=$sinceMs mtu=$mtu")
        // Give MTU negotiation + CCCD subscription time to settle. Without this, the very
        // first frame is sent at mtu=23 and the Done frame (~38 bytes) gets truncated.
        var waitedMs = 0
        while (mtu < 50 && waitedMs < 1500) {
            delay(100)
            waitedMs += 100
        }
        val pageSize = 50
        val charSize = mtu - 3                       // BLE ATT header overhead
        var cursor = sinceMs
        var total = 0
        while (true) {
            val page = store.page(cursor, pageSize)
            if (page.isEmpty()) break
            // Pack into one or more Data frames sized to fit the MTU.
            val chunks = packIntoFrames(page, charSize)
            for (frameBytes in chunks) {
                send(device, frameBytes)
                delay(20)                            // gentle pacing for slow LE stacks
            }
            total += page.size
            cursor = page.last().startMs
            if (page.size < pageSize) break
        }
        val newest = store.newest()
        send(device, json.encodeToString(Protocol.Frame.serializer(), Protocol.Frame.Done(newest, total)).toByteArray())
        BleState.status.value = "Sent $total samples"
        BleState.lastSyncAtMs.value = System.currentTimeMillis()
        Log.i(TAG, "stream() done total=$total newest=$newest")
    }

    private fun packIntoFrames(samples: List<Sample>, maxBytes: Int): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        var batch = mutableListOf<Sample>()
        for (s in samples) {
            batch += s
            val candidate = json.encodeToString(Protocol.Frame.serializer(), Protocol.Frame.Data(batch)).toByteArray()
            if (candidate.size > maxBytes && batch.size > 1) {
                batch.removeLast()
                out += json.encodeToString(Protocol.Frame.serializer(), Protocol.Frame.Data(batch)).toByteArray()
                batch = mutableListOf(s)
            }
        }
        if (batch.isNotEmpty()) {
            out += json.encodeToString(Protocol.Frame.serializer(), Protocol.Frame.Data(batch)).toByteArray()
        }
        return out
    }

    private fun send(device: BluetoothDevice, payload: ByteArray) {
        val ch = streamChar ?: return
        ch.value = payload
        runCatching { server?.notifyCharacteristicChanged(device, ch, false) }
    }

    private suspend fun currentStatusJson(): ByteArray {
        val newest = store.newest()
        val pending = store.pending(newest)         // total visible from a cursor=newest perspective
        val s = Protocol.Status(newestMs = newest, pending = pending)
        return json.encodeToString(Protocol.Status.serializer(), s).toByteArray()
    }

    private suspend fun refreshStatus() {
        // Push a STATUS notification every 60s for any subscribed central.
        while (server != null) {
            val ch = statusChar
            val sub = subscriber
            if (ch != null && sub != null) {
                ch.value = currentStatusJson()
                runCatching { server?.notifyCharacteristicChanged(sub, ch, false) }
            }
            delay(60_000)
        }
    }

    private fun leLongFromBytes(b: ByteArray): Long {
        var v = 0L
        for (i in 0 until 8) v = v or ((b[i].toLong() and 0xff) shl (i * 8))
        return v
    }

    companion object { private const val TAG = "GhbGatt" }
}
