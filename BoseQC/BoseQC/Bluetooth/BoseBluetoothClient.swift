import Foundation
import CoreBluetooth
import Combine
import os.log

private let log = Logger(subsystem: "app.boseqc.macos", category: "ble")

enum BoseBLE {
    static let service = CBUUID(string: "FEBE")
    /// Prefer unsecure first — secure often needs bonding and silently drops writes.
    static let unsecure = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
    static let secure = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
    static let nameHints = ["bose", "quietcomfort", "qc ", "nc ", "ultra", "onyx", "dark star"]
}

enum ConnectionPhase: String, Equatable {
    case idle
    case poweredOff
    case unauthorized
    case scanning
    case connecting
    case discovering
    case ready
    case failed
}

struct DiscoveredHeadphone: Identifiable, Equatable {
    var id: UUID { peripheralID }
    var peripheralID: UUID
    var name: String
    var rssi: Int
}

struct LiveHeadphoneState: Equatable {
    var name: String = "—"
    var batteryPercent: Int?
    var modeIndex: UInt8?
    var modeLabel: String?
    var lastError: String?
}

/// CoreBluetooth BMAP client. Write path matches NerdySouth/bozo:
/// always `writeWithoutResponse`, notify subscribed before any packet.
@MainActor
final class BoseBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var discovered: [DiscoveredHeadphone] = []
    @Published private(set) var state = LiveHeadphoneState()
    @Published private(set) var statusMessage: String = "Idle"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyReady = false
    private var didBroadServiceScan = false
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private let reassembler = BmapSegmenter.Reassembler()
    private var pendingByKey: [UInt16: CheckedContinuation<BmapPacket, Error>] = [:]
    private var sendChain: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        discovered = []
        guard central.state == .poweredOn else {
            statusMessage = "Bluetooth not ready"
            return
        }
        phase = .scanning
        statusMessage = "Scanning…"
        central.scanForPeripherals(withServices: [BoseBLE.service], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.phase == .scanning else { return }
            self.central.stopScan()
            self.central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func stopScan() {
        central.stopScan()
        if phase == .scanning {
            phase = .idle
            statusMessage = "Stopped"
        }
    }

    func connect(to item: DiscoveredHeadphone) {
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [item.peripheralID]).first
                ?? knownPeripherals[item.peripheralID] else {
            statusMessage = "Device not found"
            return
        }
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        phase = .connecting
        notifyReady = false
        didBroadServiceScan = false
        statusMessage = "Connecting…"
        state = LiveHeadphoneState(name: item.name)
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection(message: "Disconnected")
    }

    func refresh() async {
        guard phase == .ready else { return }
        statusMessage = "Syncing…"
        do {
            // Serialize — parallel GETs race on one characteristic.
            _ = try await queryName()
            _ = try await queryBattery()
            _ = try await queryMode()
            state.lastError = nil
            statusMessage = "Ready"
        } catch {
            state.lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func setMode(index: UInt8) async {
        guard phase == .ready else { return }
        statusMessage = "Changing mode…"
        do {
            // bozo: START with voice_prompt = 0x00; may not always STATUS back.
            _ = try await send(BmapCommands.setMode(index: index, voicePrompt: false), waitForReply: true)
            try await Task.sleep(nanoseconds: 250_000_000)
            _ = try await queryMode()
            state.lastError = nil
            statusMessage = "Ready"
        } catch {
            // Even if START times out, re-query — some firmware applies without STATUS.
            if let mode = try? await queryMode() {
                state.modeIndex = mode
                state.lastError = nil
                statusMessage = "Ready"
                return
            }
            state.lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Queries

    private func queryBattery() async throws -> Int {
        let packet = try await send(BmapCommands.queryBattery)
        guard let percent = packet.payload.first.map(Int.init) else { throw BoseError.emptyPayload }
        state.batteryPercent = percent
        return percent
    }

    private func queryName() async throws -> String {
        let packet = try await send(BmapCommands.queryName)
        let cleaned = packet.payload.filter { $0 != 0 }
        if let name = String(bytes: cleaned, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            state.name = name
            return name
        }
        return state.name
    }

    private func queryMode() async throws -> UInt8 {
        let packet = try await send(BmapCommands.queryCurrentMode)
        guard let index = packet.payload.first else { throw BoseError.emptyPayload }
        state.modeIndex = index
        if let config = try? await send(BmapCommands.queryModeConfig(index: index)),
           config.payload.count >= 7 {
            let end = min(38, config.payload.count)
            let nameBytes = config.payload.subdata(in: 6..<end).prefix { $0 != 0 }
            if let label = String(bytes: nameBytes, encoding: .utf8), !label.isEmpty {
                state.modeLabel = label
            } else if config.payload.count > 2 {
                state.modeLabel = Self.promptName(config.payload[2])
            }
        } else {
            state.modeLabel = ["Quiet", "Aware", "Commute"][safe: Int(index)] ?? "Mod \(index)"
        }
        return index
    }

    private static func promptName(_ id: UInt8) -> String {
        switch id {
        case 1: return "Quiet"
        case 2: return "Aware"
        case 7: return "Commute"
        case 34: return "Immersion"
        case 36: return "Cinema"
        default: return "Mod"
        }
    }

    // MARK: - Transport

    private func send(_ packet: BmapPacket, waitForReply: Bool = true) async throws -> BmapPacket {
        guard phase == .ready, notifyReady, let peripheral, let writeCharacteristic else {
            throw BoseError.notReady
        }

        // Queue sends so segments never interleave.
        return try await withCheckedThrowingContinuation { (outer: CheckedContinuation<BmapPacket, Error>) in
            let previous = sendChain
            sendChain = Task { @MainActor in
                _ = await previous?.value
                do {
                    let result = try await self.performSend(packet, waitForReply: waitForReply, peripheral: peripheral, characteristic: writeCharacteristic)
                    outer.resume(returning: result)
                } catch {
                    outer.resume(throwing: error)
                }
            }
        }
    }

    private func performSend(
        _ packet: BmapPacket,
        waitForReply: Bool,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) async throws -> BmapPacket {
        let key = UInt16(packet.block) << 8 | UInt16(packet.function)
        let encoded = packet.encode()
        let segments = BmapSegmenter.segment(encoded)
        log.info("TX \(encoded.map { String(format: "%02X", $0) }.joined(separator: " ")) via \(characteristic.uuid.uuidString)")

        if !waitForReply {
            for segment in segments {
                // bozo always uses WithoutResponse
                peripheral.writeValue(segment, for: characteristic, type: .withoutResponse)
            }
            return packet
        }

        return try await withCheckedThrowingContinuation { cont in
            if let old = pendingByKey.removeValue(forKey: key) {
                old.resume(throwing: BoseError.superseded)
            }
            pendingByKey[key] = cont
            for segment in segments {
                peripheral.writeValue(segment, for: characteristic, type: .withoutResponse)
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await self?.failPending(key: key, error: BoseError.timeout)
            }
        }
    }

    private func failPending(key: UInt16, error: Error) {
        if let cont = pendingByKey.removeValue(forKey: key) {
            cont.resume(throwing: error)
        }
    }

    private func handleIncoming(_ data: Data) {
        guard let assembled = reassembler.push(data) else { return }
        log.info("RX \(assembled.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Device may concatenate multiple BMAP packets in one reassembly.
        var offset = 0
        while offset + 4 <= assembled.count {
            let length = Int(assembled[offset + 3])
            let end = offset + 4 + length
            guard end <= assembled.count,
                  let packet = BmapPacket.decode(assembled.subdata(in: offset..<end)) else { break }
            offset = end
            deliver(packet)
        }
    }

    private func deliver(_ packet: BmapPacket) {
        let key = UInt16(packet.block) << 8 | UInt16(packet.function)
        switch packet.op {
        case BmapOperator.error.rawValue:
            let code = packet.payload.first.map { String(format: "0x%02X", $0) } ?? "?"
            pendingByKey.removeValue(forKey: key)?.resume(throwing: BoseError.deviceError(code))
        case BmapOperator.status.rawValue, BmapOperator.result.rawValue:
            if let cont = pendingByKey.removeValue(forKey: key) {
                cont.resume(returning: packet)
            } else if pendingByKey.count == 1, let onlyKey = pendingByKey.keys.first,
                      let cont = pendingByKey.removeValue(forKey: onlyKey) {
                // Some firmwares reply under a neighboring function id.
                cont.resume(returning: packet)
            }
        case BmapOperator.processing.rawValue:
            break
        default:
            break
        }
    }

    private func resetConnection(message: String) {
        writeCharacteristic = nil
        peripheral = nil
        notifyReady = false
        didBroadServiceScan = false
        reassembler.reset()
        for (_, cont) in pendingByKey { cont.resume(throwing: BoseError.disconnected) }
        pendingByKey.removeAll()
        phase = .idle
        statusMessage = message
    }

    private func pickCharacteristic(from chars: [CBCharacteristic]) -> CBCharacteristic? {
        chars.first(where: { $0.uuid == BoseBLE.unsecure })
            ?? chars.first(where: { $0.uuid == BoseBLE.secure })
            ?? chars.first
    }
}

enum BoseError: LocalizedError {
    case notReady
    case timeout
    case emptyPayload
    case superseded
    case disconnected
    case deviceError(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "Not connected"
        case .timeout: return "Device did not respond"
        case .emptyPayload: return "Empty response"
        case .superseded: return "Request cancelled"
        case .disconnected: return "Disconnected"
        case .deviceError(let code): return "Device error \(code)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension BoseBluetoothClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if phase == .poweredOff || phase == .idle { phase = .idle }
                statusMessage = "Bluetooth on"
            case .poweredOff:
                phase = .poweredOff
                statusMessage = "Bluetooth off"
            case .unauthorized:
                phase = .unauthorized
                statusMessage = "Bluetooth permission needed"
            default:
                statusMessage = "Bluetooth not ready"
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let advertised = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? peripheral.name
                ?? ""
            let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let hasBmap = services.contains(BoseBLE.service)
            let lower = advertised.lowercased()
            let nameMatch = BoseBLE.nameHints.contains { lower.contains($0) }
            guard hasBmap || nameMatch else { return }

            knownPeripherals[peripheral.identifier] = peripheral
            let item = DiscoveredHeadphone(
                peripheralID: peripheral.identifier,
                name: advertised.isEmpty ? "Bose" : advertised,
                rssi: RSSI.intValue
            )
            if let idx = discovered.firstIndex(where: { $0.peripheralID == peripheral.identifier }) {
                discovered[idx] = item
            } else {
                discovered.append(item)
            }
            statusMessage = "\(discovered.count) found"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            phase = .discovering
            statusMessage = "Discovering…"
            peripheral.discoverServices([BoseBLE.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            phase = .failed
            statusMessage = error?.localizedDescription ?? "Connect failed"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            resetConnection(message: error?.localizedDescription ?? "Disconnected")
        }
    }
}

extension BoseBluetoothClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                phase = .failed
                statusMessage = error.localizedDescription
                return
            }
            if let service = peripheral.services?.first(where: { $0.uuid == BoseBLE.service }) {
                peripheral.discoverCharacteristics([BoseBLE.unsecure, BoseBLE.secure], for: service)
                return
            }
            if !didBroadServiceScan {
                didBroadServiceScan = true
                peripheral.discoverServices(nil)
                return
            }
            phase = .failed
            statusMessage = "No BMAP service (FEBE)"
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                phase = .failed
                statusMessage = error.localizedDescription
                return
            }
            guard let chosen = pickCharacteristic(from: service.characteristics ?? []) else {
                phase = .failed
                statusMessage = "No BMAP characteristic"
                return
            }
            writeCharacteristic = chosen
            statusMessage = "Enabling notify…"
            if chosen.properties.contains(.notify) || chosen.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: chosen)
            } else {
                notifyReady = true
                phase = .ready
                statusMessage = "Connected"
                Task { await refresh() }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                phase = .failed
                statusMessage = "Notify: \(error.localizedDescription)"
                return
            }
            guard characteristic.isNotifying else {
                phase = .failed
                statusMessage = "Notify failed"
                return
            }
            notifyReady = true
            phase = .ready
            statusMessage = "Connected"
            log.info("notify OK on \(characteristic.uuid.uuidString)")
            Task { await refresh() }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                state.lastError = error.localizedDescription
                return
            }
            guard let value = characteristic.value else { return }
            handleIncoming(value)
        }
    }
}
