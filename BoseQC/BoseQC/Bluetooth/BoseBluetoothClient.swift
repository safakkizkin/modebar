import Foundation
import IOBluetooth
import Combine
import os.log

private let log = Logger(subsystem: "app.boseqc.macos", category: "rfcomm")

/// Same path as ANChor / bosectl: Classic Bluetooth RFCOMM + raw BMAP (no BLE segment byte).
enum ConnectionPhase: String, Equatable {
    case idle
    case scanning
    case connecting
    case ready
    case failed
}

struct DiscoveredHeadphone: Identifiable, Equatable {
    var id: String { address }
    var address: String
    var name: String
    var isConnected: Bool
}

struct DeviceMode: Identifiable, Equatable {
    var id: UInt8 { index }
    var index: UInt8
    var name: String
}

struct LiveHeadphoneState: Equatable {
    var name: String = "—"
    var batteryPercent: Int?
    var modeIndex: UInt8?
    var modeLabel: String?
    var modes: [DeviceMode] = []
    var lastError: String?
}

@MainActor
final class BoseBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var discovered: [DiscoveredHeadphone] = []
    @Published private(set) var state = LiveHeadphoneState()
    @Published private(set) var statusMessage: String = "Idle"

    private var channel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var pending: CheckedContinuation<Data, Error>?
    private var rxBuffer = Data()
    private let rfcommChannelID: BluetoothRFCOMMChannelID = 2

    private static let nameHints = [
        "quietcomfort", "qc ultra", "qc earbuds", "onyx", "dark star", "bose"
    ]

    func startScan() {
        phase = .scanning
        statusMessage = "Looking for paired Bose…"
        discovered = Self.pairedBoseDevices()
        if discovered.isEmpty {
            statusMessage = "No paired Bose headphones — pair in System Settings first"
            phase = .idle
        } else {
            statusMessage = "\(discovered.count) device(s)"
            phase = .idle
        }
    }

    func stopScan() {
        phase = .idle
        statusMessage = "Stopped"
    }

    /// Prefer already-connected Bose in System Settings; otherwise first paired match.
    func connectPreferred() {
        guard phase != .connecting, phase != .ready else { return }
        startScan()
        guard let target = discovered.first(where: \.isConnected) ?? discovered.first else {
            statusMessage = "No paired Bose headphones"
            phase = .idle
            return
        }
        let label = target.isConnected ? "Opening \(target.name)…" : "Connecting \(target.name)…"
        connect(to: target, status: label)
    }

    func connect(to item: DiscoveredHeadphone, status: String? = nil) {
        guard let dev = IOBluetoothDevice(addressString: item.address) else {
            statusMessage = "Device address invalid"
            phase = .failed
            return
        }
        // Already holding RFCOMM on this address.
        if phase == .ready, device?.addressString?.uppercased() == item.address.uppercased() {
            Task { await refresh() }
            return
        }
        phase = .connecting
        statusMessage = status ?? "Opening \(item.name)…"
        state = LiveHeadphoneState(name: item.name)
        device = dev

        Task { @MainActor in
            do {
                try await openRFCOMM(to: dev)
                phase = .ready
                statusMessage = "Ready"
                await refresh()
            } catch {
                phase = .failed
                statusMessage = error.localizedDescription
                state.lastError = error.localizedDescription
                // Keep discovered list so the user can retry without another Find.
                discovered = Self.pairedBoseDevices()
            }
        }
    }

    func disconnect() {
        channel?.close()
        channel = nil
        device = nil
        failPending(BoseError.disconnected)
        phase = .idle
        statusMessage = "Disconnected"
        state = LiveHeadphoneState()
    }

    func refresh() async {
        guard phase == .ready else { return }
        statusMessage = "Syncing…"
        do {
            _ = try await queryName()
            _ = try await queryBattery()
            let modes = await discoverModes()
            state.modes = modes
            _ = try await queryCurrentMode()
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
            // ANChor: START → expect RESULT (op 6)
            let packet = BmapCommands.setMode(index: index, voicePrompt: false)
            let data = try await send(packet, expectOps: [BmapOperator.result, BmapOperator.status])
            if let reply = BmapPacket.decode(data), let idx = reply.payload.first {
                state.modeIndex = idx
                state.modeLabel = state.modes.first(where: { $0.index == idx })?.name ?? "Mode \(idx)"
            } else {
                _ = try await queryCurrentMode()
            }
            state.lastError = nil
            statusMessage = "Ready"
        } catch {
            if let _ = try? await queryCurrentMode() {
                state.lastError = nil
                statusMessage = "Ready"
                return
            }
            state.lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Paired devices (deduped by address)

    private static func pairedBoseDevices() -> [DiscoveredHeadphone] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        var byAddress: [String: DiscoveredHeadphone] = [:]
        for dev in paired {
            let name = dev.name ?? ""
            let address = (dev.addressString ?? "").uppercased()
            guard !address.isEmpty else { continue }
            let lower = name.lowercased()
            let match = nameHints.contains { lower.contains($0) }
            guard match else { continue }
            // One row per Classic address — BLE LE-* aliases collapse here.
            let display = name.replacingOccurrences(of: "LE-", with: "")
            let item = DiscoveredHeadphone(
                address: address,
                name: display.isEmpty ? name : display,
                isConnected: dev.isConnected()
            )
            if let existing = byAddress[address] {
                byAddress[address] = DiscoveredHeadphone(
                    address: address,
                    name: existing.name.count >= item.name.count ? existing.name : item.name,
                    isConnected: existing.isConnected || item.isConnected
                )
            } else {
                byAddress[address] = item
            }
        }
        return byAddress.values.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - RFCOMM

    private func openRFCOMM(to device: IOBluetoothDevice) async throws {
        if !device.isConnected() {
            let open = device.openConnection(nil)
            guard open == kIOReturnSuccess || device.isConnected() else {
                throw BoseError.connectFailed
            }
            // Wait up to 5s for classic link.
            for _ in 0..<50 where !device.isConnected() {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard device.isConnected() else { throw BoseError.connectFailed }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var chan: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelSync(
                &chan,
                withChannelID: rfcommChannelID,
                delegate: self
            )
            if result == kIOReturnSuccess, let chan {
                self.channel = chan
                // Drain unsolicited boot traffic briefly, like ANChor.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    cont.resume()
                }
            } else {
                cont.resume(throwing: BoseError.rfcommFailed(result))
            }
        }
    }

    // MARK: - BMAP queries

    private func queryBattery() async throws -> Int {
        let data = try await send(BmapCommands.queryBattery, expectOps: [.status])
        guard let packet = BmapPacket.decode(data), let percent = packet.payload.first.map(Int.init) else {
            throw BoseError.emptyPayload
        }
        state.batteryPercent = percent
        return percent
    }

    private func queryName() async throws -> String {
        let data = try await send(BmapCommands.queryName, expectOps: [.status])
        guard let packet = BmapPacket.decode(data) else { return state.name }
        let cleaned = packet.payload.filter { $0 != 0 }
        if let name = String(bytes: cleaned, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            state.name = name
            return name
        }
        return state.name
    }

    private func queryCurrentMode() async throws -> UInt8 {
        let data = try await send(BmapCommands.queryCurrentMode, expectOps: [.status])
        guard let packet = BmapPacket.decode(data), let index = packet.payload.first else {
            throw BoseError.emptyPayload
        }
        state.modeIndex = index
        if let known = state.modes.first(where: { $0.index == index }) {
            state.modeLabel = known.name
        } else if let name = try? await modeName(for: index) {
            state.modeLabel = name
        } else {
            state.modeLabel = "Mode \(index)"
        }
        return index
    }

    private func discoverModes() async -> [DeviceMode] {
        var modes: [DeviceMode] = []
        let maxIndex: UInt8
        if let caps = try? await send(BmapCommands.queryCapabilities, expectOps: [.status]),
           let packet = BmapPacket.decode(caps),
           packet.payload.count >= 2 {
            let bose = Int(packet.payload[0])
            let user = Int(packet.payload[1])
            maxIndex = UInt8(max(0, min(bose + user, 16) - 1))
        } else {
            maxIndex = 7
        }

        for index in 0...maxIndex {
            if let name = try? await modeName(for: index), !name.isEmpty {
                modes.append(DeviceMode(index: index, name: name))
            }
        }
        return modes
    }

    private func modeName(for index: UInt8) async throws -> String {
        let data = try await send(BmapCommands.queryModeConfig(index: index), expectOps: [.status])
        guard let packet = BmapPacket.decode(data), packet.payload.count >= 7 else {
            throw BoseError.emptyPayload
        }
        let end = min(38, packet.payload.count)
        let nameBytes = packet.payload.subdata(in: 6..<end).prefix { $0 != 0 }
        if let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty {
            return name
        }
        if packet.payload.count > 2 {
            return Self.promptName(packet.payload[2])
        }
        return "Mode \(index)"
    }

    private static func promptName(_ id: UInt8) -> String {
        switch id {
        case 1: return "Quiet"
        case 2: return "Aware"
        case 3, 4: return "Transparent"
        case 7: return "Commute"
        case 34: return "Immersion"
        case 36: return "Cinema"
        default: return "Mode"
        }
    }

    // MARK: - Transport (raw BMAP on RFCOMM — no BLE 0x00 framing)

    private func send(_ packet: BmapPacket, expectOps: [BmapOperator]) async throws -> Data {
        guard let channel else { throw BoseError.notReady }
        let encoded = packet.encode()
        log.info("TX \(encoded.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let data: Data = try await withCheckedThrowingContinuation { cont in
            if let old = pending {
                old.resume(throwing: BoseError.superseded)
            }
            pending = cont
            rxBuffer.removeAll()

            var bytes = [UInt8](encoded)
            let ok = bytes.withUnsafeMutableBufferPointer { buf -> Bool in
                channel.writeSync(buf.baseAddress!, length: UInt16(buf.count)) == kIOReturnSuccess
            }
            if !ok {
                pending = nil
                cont.resume(throwing: BoseError.writeFailed)
                return
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if self.pending != nil {
                    self.failPending(BoseError.timeout)
                }
            }
        }

        if let reply = BmapPacket.decode(data) {
            if reply.op == BmapOperator.error.rawValue {
                let code = reply.payload.first.map { String(format: "0x%02X", $0) } ?? "?"
                throw BoseError.deviceError(code)
            }
            if !expectOps.isEmpty {
                let ops = Set(expectOps.map(\.rawValue))
                if !ops.contains(reply.op) {
                    log.warning("unexpected op \(reply.op), wanted \(expectOps.map(\.rawValue))")
                }
            }
        }
        return data
    }

    private func failPending(_ error: Error) {
        pending?.resume(throwing: error)
        pending = nil
    }

    private func handleRX(_ bytes: [UInt8]) {
        log.info("RX \(bytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " "))")
        let data = Data(bytes)

        // Unsolicited mode STATUS
        if let packet = BmapPacket.decode(data),
           packet.block == BmapBlock.audioModes.rawValue,
           packet.function == 0x03,
           packet.op == BmapOperator.status.rawValue,
           let idx = packet.payload.first {
            state.modeIndex = idx
            state.modeLabel = state.modes.first(where: { $0.index == idx })?.name ?? state.modeLabel
        }

        guard pending != nil else { return }
        // Accept first parseable BMAP reply for the waiter (ANChor style).
        if BmapPacket.decode(data) != nil {
            let cont = pending
            pending = nil
            cont?.resume(returning: data)
        }
    }
}

enum BoseError: LocalizedError {
    case notReady
    case timeout
    case emptyPayload
    case superseded
    case disconnected
    case connectFailed
    case writeFailed
    case rfcommFailed(IOReturn)
    case deviceError(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "Not connected"
        case .timeout: return "Device did not respond"
        case .emptyPayload: return "Empty response"
        case .superseded: return "Request cancelled"
        case .disconnected: return "Disconnected"
        case .connectFailed: return "Bluetooth connect failed"
        case .writeFailed: return "RFCOMM write failed"
        case .rfcommFailed(let code): return "RFCOMM open failed (\(code))"
        case .deviceError(let code): return "Device error \(code)"
        }
    }
}

extension BoseBluetoothClient: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        Task { @MainActor in
            self.handleRX(bytes)
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Task { @MainActor in
            self.channel = nil
            self.failPending(BoseError.disconnected)
            self.phase = .idle
            self.statusMessage = "Disconnected"
        }
    }
}
