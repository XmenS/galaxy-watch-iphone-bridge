import Foundation
import os

/// Orchestrates "download from API → write to HealthKit". Idempotent — safe to call repeatedly.
@MainActor
final class SyncClient {
    private let api: ApiClient
    private let store: LocalStore
    private let hk: HealthKitManager
    private let log = Logger(subsystem: "dev.galaxyhealthbridge", category: "sync")

    init(api: ApiClient, store: LocalStore, hk: HealthKitManager) {
        self.api = api
        self.store = store
        self.hk = hk
    }

    /// Pull pages until exhausted or maxBatches reached.
    @discardableResult
    func runOnce(maxBatches: Int = 8) async throws -> RunSummary {
        var totalWritten = 0
        var totalSkipped = 0
        var cursor = store.cursor

        for _ in 0..<maxBatches {
            let page = try await api.samples(cursor: cursor, limit: 500)
            if page.items.isEmpty { break }
            let outcome = try await hk.save(page.items)
            totalWritten += outcome.written
            totalSkipped += outcome.skipped
            cursor = page.nextCursor
            store.cursor = cursor
            log.info("sync.page written=\(outcome.written) skipped=\(outcome.skipped) cursor=\(cursor ?? "nil", privacy: .public)")
            if cursor == nil { break }
        }

        return RunSummary(written: totalWritten, skipped: totalSkipped, cursor: cursor)
    }

    struct RunSummary {
        let written: Int
        let skipped: Int
        let cursor: String?
    }
}
