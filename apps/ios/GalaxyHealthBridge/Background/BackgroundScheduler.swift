import BackgroundTasks
import Foundation
import os

enum BackgroundScheduler {
    static let refreshId    = "dev.galaxyhealthbridge.refresh"
    static let processingId = "dev.galaxyhealthbridge.processing"
    private static let log = Logger(subsystem: "dev.galaxyhealthbridge", category: "bg")

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshId, using: nil) { task in
            handleRefresh(task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingId, using: nil) { task in
            handleProcessing(task as! BGProcessingTask)
        }
    }

    static func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshId)
        req.earliestBeginDate = Date().addingTimeInterval(60 * 30)  // 30 min hint; iOS may delay
        do {
            try BGTaskScheduler.shared.submit(req)
            log.info("bg.refresh scheduled")
        } catch {
            log.warning("bg.refresh schedule failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func scheduleNextProcessing() {
        let req = BGProcessingTaskRequest(identifier: processingId)
        req.earliestBeginDate = Date().addingTimeInterval(60 * 60 * 4)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(req)
    }

    @MainActor
    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let work = Task<Void, Never> {
            do {
                let store = LocalStore()
                let summary = try await SyncClient(
                    api: .live(), store: store, hk: .live()
                ).runOnce(maxBatches: 2)
                log.info("bg.refresh done written=\(summary.written) skipped=\(summary.skipped)")
                task.setTaskCompleted(success: true)
            } catch {
                log.error("bg.refresh failed: \(String(describing: error), privacy: .public)")
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }

    @MainActor
    private static func handleProcessing(_ task: BGProcessingTask) {
        scheduleNextProcessing()
        let work = Task<Void, Never> {
            do {
                let summary = try await SyncClient(
                    api: .live(), store: LocalStore(), hk: .live()
                ).runOnce(maxBatches: 16)
                log.info("bg.processing done written=\(summary.written)")
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
