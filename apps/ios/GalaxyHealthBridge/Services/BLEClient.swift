import Foundation
import CoreBluetooth
import os

/// CoreBluetooth central that speaks the Watch's GHB protocol.
///
/// Wire contract (mirrors `apps/wearos/.../ble/Protocol.kt`):
///   - Service `e2a00001-1234-5678-9abc-def012345678`
///   - REQUEST `…0002` (write w/o response): 8-byte little-endian millis cursor
///   - STREAM  `…0003` (notify): JSON Frame envelopes, ending with `{ "kind": "done", ... }`
///   - STATUS  `…0004` (read/notify): JSON status payload
///
/// Usage:
///   let client = BLEClient()
///   for try await event in client.sync(since: cursorMs) { ... }
@MainActor
final class BLEClient: NSObject {

    enum Event {
        case scanning
        case connecting(peripheral: String)
        case syncing
        case batch([WireSample])
        case done(newestMs: Int64, total: Int)
        case error(BLEError)
    }

    enum BLEError: Error, LocalizedError {
        case bluetoothOff
        case unauthorized
        case unsupported
        case noPeripheralFound
        case disconnected
        case characteristicMissing
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .bluetoothOff: return "Turn Bluetooth on, then try again."
            case .unauthorized: return "Bluetooth permission denied. Enable it in Settings → Galaxy Health Bridge."
            case .unsupported: return "This device doesn't support Bluetooth LE."
            case .noPeripheralFound: return "Couldn't find the watch. Open HealthBridge on the watch and tap Start."
            case .disconnected: return "Watch disconnected before sync finished."
            case .characteristicMissing: return "Watch service is incomplete (missing characteristic)."
            case .decoding(let why): return "Failed to decode watch payload: \(why)"
            }
        }
    }

    static let serviceUUID = CBUUID(string: "e2a00001-1234-5678-9abc-def012345678")
    static let requestUUID = CBUUID(string: "e2a00002-1234-5678-9abc-def012345678")
    static let streamUUID  = CBUUID(string: "e2a00003-1234-5678-9abc-def012345678")
    static let statusUUID  = CBUUID(string: "e2a00004-1234-5678-9abc-def012345678")

    private lazy var manager: CBCentralManager = CBCentralManager(delegate: self, queue: .main)
    private var peripheral: CBPeripheral?
    private var requestChar: CBCharacteristic?
    private var streamChar: CBCharacteristic?
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?
    private var cursor: Int64 = 0
    private var resetRequested: Bool = false
    private let log = Logger(subsystem: "dev.galaxyhealthbridge", category: "ble")
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// One-shot scan → connect → write cursor → consume STREAM frames until Done.
    /// If `reset` is true, prefixes the cursor write with 8 sentinel bytes which the
    /// watch interprets as "wipe local sample store, then sync from cursor". Used
    /// when the user explicitly clears state on the iPhone and we need the watch's
    /// store to match.
    func sync(since cursorMs: Int64, reset: Bool = false, scanTimeout: TimeInterval = 15) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.cursor = cursorMs
            self.resetRequested = reset
            self.peripheral = nil
            self.requestChar = nil
            self.streamChar = nil
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.tearDown() }
            }
            // If the manager is already powered on (any sync after the first),
            // centralManagerDidUpdateState won't fire again — kick scanning manually.
            if manager.state == .poweredOn {
                continuation.yield(.scanning)
                if manager.isScanning { manager.stopScan() }
                manager.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
            } else {
                _ = manager   // first-time lazy init; scan starts from delegate callback
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(scanTimeout * 1_000_000_000))
                if self.peripheral == nil {
                    continuation.yield(.error(.noPeripheralFound))
                    continuation.finish()
                }
            }
        }
    }

    private func tearDown() {
        if let p = peripheral { manager.cancelPeripheralConnection(p) }
        peripheral = nil
        requestChar = nil
        streamChar = nil
        if manager.isScanning { manager.stopScan() }
        continuation = nil
    }
}

extension BLEClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                continuation?.yield(.scanning)
                central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
            case .poweredOff:
                continuation?.yield(.error(.bluetoothOff)); continuation?.finish()
            case .unauthorized:
                continuation?.yield(.error(.unauthorized)); continuation?.finish()
            case .unsupported:
                continuation?.yield(.error(.unsupported)); continuation?.finish()
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String : Any],
                                     rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            continuation?.yield(.connecting(peripheral: peripheral.name ?? peripheral.identifier.uuidString))
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            // Disconnect is expected once we emit Done; only treat as error if we never finished.
            if streamChar != nil {
                continuation?.yield(.error(.disconnected))
                continuation?.finish()
            }
        }
    }
}

extension BLEClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                continuation?.yield(.error(.characteristicMissing)); continuation?.finish(); return
            }
            peripheral.discoverCharacteristics([Self.requestUUID, Self.streamUUID, Self.statusUUID], for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        Task { @MainActor in
            for ch in service.characteristics ?? [] {
                if ch.uuid == Self.requestUUID { requestChar = ch }
                if ch.uuid == Self.streamUUID  { streamChar  = ch }
            }
            guard let stream = streamChar, requestChar != nil else {
                log.error("BLE: missing characteristics req=\(self.requestChar == nil) stream=\(self.streamChar == nil)")
                continuation?.yield(.error(.characteristicMissing)); continuation?.finish(); return
            }
            log.info("BLE: subscribing to STREAM, will write cursor on confirm")
            // Only kick off the notify subscription; defer the cursor write until the
            // watch confirms CCCD via didUpdateNotificationStateFor. Without this,
            // CoreBluetooth races the two writes and the cursor write can land
            // before subscriber is set on the watch, which prevents streaming.
            peripheral.setNotifyValue(true, for: stream)
            continuation?.yield(.syncing)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == Self.streamUUID else { return }
            if let error = error {
                log.error("BLE: notify state error: \(error.localizedDescription)")
                continuation?.yield(.error(.decoding(error.localizedDescription)))
                continuation?.finish()
                return
            }
            guard characteristic.isNotifying, let request = requestChar else { return }
            let payload: Data
            if resetRequested {
                log.info("BLE: STREAM notify confirmed; writing RESET + cursor=\(self.cursor)")
                payload = Self.resetSentinel() + Self.le64(cursor)
            } else {
                log.info("BLE: STREAM notify confirmed; writing cursor=\(self.cursor)")
                payload = Self.le64(cursor)
            }
            peripheral.writeValue(payload, for: request, type: .withResponse)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didWriteValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            if let error = error {
                log.error("BLE: write error on \(characteristic.uuid): \(error.localizedDescription)")
                continuation?.yield(.error(.decoding(error.localizedDescription)))
                continuation?.finish()
            } else {
                log.info("BLE: cursor write acknowledged")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == Self.streamUUID, let data = characteristic.value else { return }
            handleFrame(data)
        }
    }

    @MainActor
    private func handleFrame(_ data: Data) {
        do {
            let frame = try decoder.decode(WireFrame.self, from: data)
            switch frame.kind {
            case "data":
                if let items = frame.items { continuation?.yield(.batch(items)) }
            case "done":
                continuation?.yield(.done(newestMs: frame.newestMs ?? cursor, total: frame.total ?? 0))
                continuation?.finish()
            default:
                continuation?.yield(.error(.decoding("unknown frame kind \(frame.kind)")))
                continuation?.finish()
            }
        } catch {
            continuation?.yield(.error(.decoding(error.localizedDescription)))
            continuation?.finish()
        }
    }

    private static func le64(_ value: Int64) -> Data {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }

    /// 8 bytes of 0xFF the watch interprets as "wipe local store before streaming".
    /// Mirrors the parsing in `GattServer.onCharacteristicWriteRequest`.
    private static func resetSentinel() -> Data {
        Data(repeating: 0xFF, count: 8)
    }
}

/// Mirror of `Sample` from the Wear OS side (compact field names because BLE MTU is small).
struct WireSample: Decodable {
    let uid: String
    let t: String                  // "hr","steps","cal","dist","sleep_*"
    let v: Double?
    let u: String?
    let s: Int64                   // start millis
    let e: Int64                   // end millis
}

private struct WireFrame: Decodable {
    let kind: String
    let items: [WireSample]?
    let newestMs: Int64?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case kind, items, total
        case newestMs = "newest_ms"
    }
}
