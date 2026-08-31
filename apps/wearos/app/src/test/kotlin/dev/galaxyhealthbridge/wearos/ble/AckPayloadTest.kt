package dev.galaxyhealthbridge.wearos.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AckPayloadTest {
    @Test
    fun parsesLittleEndianCursor() {
        val bytes = byteArrayOf(0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01)
        assertEquals(0x0102030405060708L, AckPayload.parse(bytes)?.cursorMs)
    }

    @Test
    fun rejectsShortPayload() {
        assertNull(AckPayload.parse(ByteArray(7)))
    }
}
