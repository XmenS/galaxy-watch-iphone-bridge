package dev.galaxyhealthbridge.wearos.ble

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * BLE wire contract between the Watch (peripheral) and the iPhone (central).
 *
 * Service contains three characteristics:
 *   - REQUEST  (write w/o response): central writes 8-byte little-endian millis-since-epoch
 *               representing the cursor it last successfully ingested.
 *   - STREAM   (notify): peripheral pushes Frame JSON chunks until it sends a Done frame.
 *   - STATUS   (read/notify): JSON describing peripheral state (newest sample timestamp,
 *               pending count) — used by central for UI without forcing a full sync.
 */
object Protocol {
    val SERVICE_UUID: UUID  = UUID.fromString("e2a00001-1234-5678-9abc-def012345678")
    val REQUEST_UUID: UUID  = UUID.fromString("e2a00002-1234-5678-9abc-def012345678")
    val STREAM_UUID: UUID   = UUID.fromString("e2a00003-1234-5678-9abc-def012345678")
    val STATUS_UUID: UUID   = UUID.fromString("e2a00004-1234-5678-9abc-def012345678")
    // Standard Bluetooth descriptor for Client Characteristic Configuration (enables notify).
    val CCCD_UUID: UUID     = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Frame envelope sent over the STREAM characteristic. */
    @Serializable
    sealed interface Frame {
        @Serializable
        @SerialName("data")
        data class Data(val items: List<Sample>) : Frame

        @Serializable
        @SerialName("done")
        data class Done(@SerialName("newest_ms") val newestMs: Long, val total: Int) : Frame
    }

    /** Status payload (read via STATUS char). */
    @Serializable
    data class Status(
        @SerialName("newest_ms") val newestMs: Long,
        val pending: Int,
        val battery: Int = -1,
    )
}

/** Canonical health sample on the wire. Compact field names because BLE MTU is small. */
@Serializable
data class Sample(
    val uid: String,                 // stable id (deterministic UUID from source row)
    val t: String,                   // canonical type: "hr","steps","cal","dist","sleep_*"
    val v: Double? = null,           // value (null for category samples)
    val u: String? = null,           // unit
    @SerialName("s") val startMs: Long,
    @SerialName("e") val endMs: Long,
)

/** Decoded form of a write to the REQUEST characteristic. Extracted from
 *  [dev.galaxyhealthbridge.wearos.ble.GattServer.onCharacteristicWriteRequest]
 *  so it can be unit-tested without a real GATT server. */
data class RequestPayload(val reset: Boolean, val cursorMs: Long) {
    companion object {
        /** 8 leading 0xFF bytes signal "wipe the watch's local sample store before streaming". */
        private val RESET_PREFIX: ByteArray = ByteArray(8) { 0xFF.toByte() }

        fun parse(bytes: ByteArray): RequestPayload {
            val isReset = bytes.size >= 16 &&
                bytes.copyOfRange(0, 8).contentEquals(RESET_PREFIX)
            val cursorBytes = if (isReset) bytes.copyOfRange(8, 16) else bytes
            val cursorMs = if (cursorBytes.size >= 8) leLong(cursorBytes) else 0L
            return RequestPayload(reset = isReset, cursorMs = cursorMs)
        }

        private fun leLong(b: ByteArray): Long =
            (b[0].toLong() and 0xff) or
            ((b[1].toLong() and 0xff) shl 8) or
            ((b[2].toLong() and 0xff) shl 16) or
            ((b[3].toLong() and 0xff) shl 24) or
            ((b[4].toLong() and 0xff) shl 32) or
            ((b[5].toLong() and 0xff) shl 40) or
            ((b[6].toLong() and 0xff) shl 48) or
            ((b[7].toLong() and 0xff) shl 56)
    }
}
