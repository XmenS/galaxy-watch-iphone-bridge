package dev.galaxyhealthbridge.wearos.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestPayloadTest {

    @Test
    fun `8 byte payload decodes as a plain cursor write`() {
        // Cursor = 0x0123456789ABCDEF, little-endian
        val bytes = byteArrayOf(
            0xEF.toByte(), 0xCD.toByte(), 0xAB.toByte(), 0x89.toByte(),
            0x67.toByte(), 0x45.toByte(), 0x23.toByte(), 0x01.toByte(),
        )
        val payload = RequestPayload.parse(bytes)
        assertFalse("8-byte payload must not be treated as reset", payload.reset)
        assertEquals(0x0123456789ABCDEFL, payload.cursorMs)
    }

    @Test
    fun `16 byte payload with 0xFF prefix decodes as a reset write`() {
        val cursor = byteArrayOf(
            0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        )
        val bytes = ByteArray(8) { 0xFF.toByte() } + cursor
        val payload = RequestPayload.parse(bytes)
        assertTrue("16-byte 0xFF-prefixed payload must trigger reset", payload.reset)
        assertEquals(0x1000L, payload.cursorMs)
    }

    @Test
    fun `16 bytes without 0xFF prefix is not treated as reset`() {
        // First 8 bytes look like a real cursor, second 8 bytes look like junk.
        val first = byteArrayOf(0x10, 0x00, 0, 0, 0, 0, 0, 0)
        val second = byteArrayOf(0x20, 0x00, 0, 0, 0, 0, 0, 0)
        val payload = RequestPayload.parse(first + second)
        assertFalse(payload.reset)
        // Parser falls back to interpreting the first 8 bytes as the cursor.
        assertEquals(0x10L, payload.cursorMs)
    }

    @Test
    fun `empty or truncated payload yields cursor zero`() {
        assertEquals(0L, RequestPayload.parse(ByteArray(0)).cursorMs)
        assertEquals(0L, RequestPayload.parse(ByteArray(4)).cursorMs)
    }

    @Test
    fun `zero cursor with reset prefix still parses as reset with cursor zero`() {
        val bytes = ByteArray(8) { 0xFF.toByte() } + ByteArray(8) { 0x00 }
        val payload = RequestPayload.parse(bytes)
        assertTrue(payload.reset)
        assertEquals(0L, payload.cursorMs)
    }
}
