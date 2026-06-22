package dev.galaxyhealthbridge.android.health.samsung

/**
 * Stub for the Samsung Health Data SDK. The SDK is partner-gated; we keep this
 * as a fallback path for metrics that Health Connect doesn't surface (e.g.
 * historical stress, ECG strips). For v1 we ship Health Connect only and leave
 * this as a deliberate extension point.
 *
 * VALIDATED: API surface exists (Samsung Health Data SDK 1.x, 2024).
 * BLOCKER:   Production access requires Samsung Health Platform partner approval.
 */
class SamsungHealthAdapter {
    fun isAvailable(): Boolean = false
}
