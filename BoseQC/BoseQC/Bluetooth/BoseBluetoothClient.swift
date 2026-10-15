import Foundation
import IOBluetooth
import Combine
import os.log

private let log = Logger(subsystem: "app.boseqc.macos", category: "rfcomm")

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

/// RFCOMM + BMAP on a dedicated thread (ANChor pattern). Main-thread sync opens hang forever.
@MainActor
final class BoseBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var discovered: [DiscoveredHeadphone] = []
    @Published private(set) var state = LiveHeadphoneState()
    @Published private(set) var statusMessage: String = "Idle"

    private let worker = RFCOMMWorker()

    private static let nameHints = [
        "quietcomfort", "qc ultra", "qc earbuds", "onyx", "dark star", "bose"
    ]

    override init() {
        super.init()
        worker.onClosed = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.phase == .ready || self.phase == .connecting {
                    self.phase = .idle
                    self.statusMessage = "Disconnected"
                    self.state.lastError = nil
                }
            }
        }
    }

    func startScan() {
        phase = .scanning
        statusMessage = "Looking for paired Bose…"
        discovered = Self.pairedBoseDevices()
        phase = .idle
        if discovered.isEmpty {
            statusMessage = "No paired Bose headphones — pair in System Settings first"
        } else {
            statusMessage = "\(discovered.count) device(s)"
        }
    }

    func stopScan() {
        phase = .idle
        statusMessage = "Stopped"
    }

    func connectPreferred() {
        guard phase != .connecting, phase != .ready else { return }
        startScan()
        guard let target = discovered.first(where: \.isConnected) ?? discovered.first else {
            statusMessage = "No paired Bose headphones"
            phase = .idle
            return
        }
        connect(to: target)
    }

    func connect(to item: DiscoveredHeadphone) {
        guard phase != .connecting else { return }
        phase = .connecting
        statusMessage = item.isConnected ? "Opening \(item.name)…" : "Connecting \(item.name)…"
        state = LiveHeadphoneState(name: item.name)
        discovered = Self.pairedBoseDevices()

        Task { @MainActor in
            do {
                try await worker.open(address: item.address, name: item.name, timeout: 8)
                phase = .ready
                statusMessage = "Ready"
                await refresh()
            } catch {
                phase = .failed
                statusMessage = error.localizedDescription
                state.lastError = error.localizedDescription
                discovered = Self.pairedBoseDevices()
            }
        }
    }

    func disconnect() {
        worker.close()
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
            state.modes = await discoverModes()
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
            _ = try await worker.send(BmapCommands.setMode(index: index, voicePrompt: false).encode(), timeout: 2.5)
            try? await Task.sleep(nanoseconds: 150_000_000)
            _ = try await queryCurrentMode()
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

    // MARK: - Queries

    private func queryBattery() async throws -> Int {
        let data = try await worker.send(BmapCommands.queryBattery.encode(), timeout: 2.5)
        guard let packet = BmapPacket.decode(data), let percent = packet.payload.first.map(Int.init) else {
            throw BoseError.emptyPayload
        }
        if packet.op == BmapOperator.error.rawValue {
            throw BoseError.deviceError(packet.payload.first.map { String(format: "0x%02X", $0) } ?? "?")
        }
        state.batteryPercent = percent
        return percent
    }

    private func queryName() async throws -> String {
        let data = try await worker.send(BmapCommands.queryName.encode(), timeout: 2.5)
        guard let packet = BmapPacket.decode(data) else { return state.name }
        if packet.op == BmapOperator.error.rawValue { return state.name }
        let cleaned = packet.payload.filter { $0 != 0 }
        if let name = String(bytes: cleaned, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            state.name = name
        }
        return state.name
    }

    private func queryCurrentMode() async throws -> UInt8 {
        let data = try await worker.send(BmapCommands.queryCurrentMode.encode(), timeout: 2.5)
        guard let packet = BmapPacket.decode(data), let index = packet.payload.first else {
            throw BoseError.emptyPayload
        }
        if packet.op == BmapOperator.error.rawValue {
            throw BoseError.deviceError(packet.payload.first.map { String(format: "0x%02X", $0) } ?? "?")
        }
        state.modeIndex = index
        if let known = state.modes.first(where: { $0.index == index })?.name {
            state.modeLabel = known
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
        if let caps = try? await worker.send(BmapCommands.queryCapabilities.encode(), timeout: 2.0),
           let packet = BmapPacket.decode(caps),
           packet.op == BmapOperator.status.rawValue,
           packet.payload.count >= 2 {
            let total = Int(packet.payload[0]) + Int(packet.payload[1])
            maxIndex = UInt8(max(0, min(total, 12) - 1))
        } else {
            maxIndex = 5
        }
        for index in 0...maxIndex {
            if let name = try? await modeName(for: index), !name.isEmpty {
                modes.append(DeviceMode(index: index, name: name))
            }
        }
        return modes
    }

    private func modeName(for index: UInt8) async throws -> String {
        let data = try await worker.send(BmapCommands.queryModeConfig(index: index).encode(), timeout: 2.0)
        guard let packet = BmapPacket.decode(data),
              packet.op == BmapOperator.status.rawValue,
              packet.payload.count >= 7 else {
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

    private static func pairedBoseDevices() -> [DiscoveredHeadphone] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        var byAddress: [String: DiscoveredHeadphone] = [:]
        for dev in paired {
            let name = dev.name ?? ""
            let address = (dev.addressString ?? "").uppercased()
            guard !address.isEmpty else { continue }
            let lower = name.lowercased()
            guard nameHints.contains(where: { lower.contains($0) }) else { continue }
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
}

// MARK: - Background RFCOMM worker (owns the IOBluetooth RunLoop)

private final class RFCOMMWorker: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var onClosed: (() -> Void)?

    private var thread: Thread!
    private var runLoop: RunLoop?
    private let ready = DispatchSemaphore(value: 0)

    private var channel: IOBluetoothRFCOMMChannel?
    private var activeBox: SendBox?
    private var openCont: CheckedContinuation<Void, Error>?
    private let openLock = NSLock()

    override init() {
        super.init()
        let boot = ready
        thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = RunLoop.current
            let port = Port()
            RunLoop.current.add(port, forMode: .default)
            boot.signal()
            RunLoop.current.run()
        }
        thread.name = "BoseQC-RFCOMM"
        thread.start()
        ready.wait()
    }

    func open(address: String, name: String, timeout: TimeInterval) async throws {
        close()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            openLock.lock()
            openCont = cont
            openLock.unlock()
            perform(#selector(doOpen(_:)), on: thread, with: ["address": address, "name": name] as NSDictionary, waitUntilDone: false)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                guard self.finishOpen(.failure(BoseError.timeout)) else { return }
                self.perform(#selector(self.doClose), on: self.thread, with: nil, waitUntilDone: false)
            }
        }
    }

    func close() {
        perform(#selector(doClose), on: thread, with: nil, waitUntilDone: false)
    }

    func send(_ bytes: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let box = SendBox(data: bytes, cont: cont)
            perform(#selector(doSendBox(_:)), on: thread, with: box, waitUntilDone: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self, weak box] in
                guard let self, let box else { return }
                guard box.finish(.failure(BoseError.timeout)) else { return }
                self.perform(#selector(self.clearPending), on: self.thread, with: nil, waitUntilDone: false)
            }
        }
    }

    @objc private func doOpen(_ info: NSDictionary) {
        let address = info["address"] as? String ?? ""
        guard let device = IOBluetoothDevice(addressString: address) else {
            finishOpen(.failure(BoseError.connectFailed))
            return
        }
        log.info("RFCOMM open \(address, privacy: .public) connected=\(device.isConnected())")

        if !device.isConnected() {
            _ = device.openConnection(nil)
            let deadline = Date().addingTimeInterval(4)
            while !device.isConnected(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            guard device.isConnected() else {
                finishOpen(.failure(BoseError.connectFailed))
                return
            }
        }

        var chan: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&chan, withChannelID: 2, delegate: self)
        log.info("RFCOMM result=\(result)")
        if result == kIOReturnSuccess, let chan {
            channel = chan
            // Drain boot chatter.
            let drainEnd = Date().addingTimeInterval(0.5)
            while Date() < drainEnd {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            finishOpen(.success(()))
        } else {
            finishOpen(.failure(BoseError.rfcommFailed(result)))
        }
    }

    @objc private func doClose() {
        _ = channel?.close()
        channel = nil
    }

    @objc private func clearPending() {
        activeBox = nil
    }

    @objc private func doSendBox(_ box: SendBox) {
        guard let channel else {
            _ = box.finish(.failure(BoseError.notReady))
            return
        }
        activeBox = box
        var bytes = [UInt8](box.data)
        log.info("TX \(box.data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        let ok = bytes.withUnsafeMutableBufferPointer { buf in
            channel.writeSync(buf.baseAddress!, length: UInt16(buf.count)) == kIOReturnSuccess
        }
        if !ok {
            activeBox = nil
            _ = box.finish(.failure(BoseError.writeFailed))
        }
    }

    @discardableResult
    private func finishOpen(_ result: Result<Void, Error>) -> Bool {
        openLock.lock()
        defer { openLock.unlock() }
        guard let openCont else { return false }
        self.openCont = nil
        switch result {
        case .success: openCont.resume()
        case .failure(let error): openCont.resume(throwing: error)
        }
        return true
    }

    // MARK: Delegate

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        log.info("RX \(bytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " "))")
        let data = Data(bytes)
        guard BmapPacket.decode(data) != nil, let box = activeBox else { return }
        activeBox = nil
        _ = box.finish(.success(data))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log.info("RFCOMM closed")
        channel = nil
        if let box = activeBox {
            activeBox = nil
            _ = box.finish(.failure(BoseError.disconnected))
        }
        _ = finishOpen(.failure(BoseError.disconnected))
        onClosed?()
    }
}

/// NSObject box so we can `perform(_:on:with:)` an async continuation + payload.
private final class SendBox: NSObject {
    let data: Data
    private let cont: CheckedContinuation<Data, Error>
    private let lock = NSLock()
    private var finished = false

    init(data: Data, cont: CheckedContinuation<Data, Error>) {
        self.data = data
        self.cont = cont
    }

    /// Returns true if this call won the race to finish.
    func finish(_ result: Result<Data, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        switch result {
        case .success(let data): cont.resume(returning: data)
        case .failure(let error): cont.resume(throwing: error)
        }
        return true
    }
}

enum BoseError: LocalizedError {
    case notReady
    case timeout
    case emptyPayload
    case disconnected
    case connectFailed
    case writeFailed
    case rfcommFailed(IOReturn)
    case deviceError(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "Not connected"
        case .timeout: return "Timed out opening headphones — toggle Bluetooth or reconnect once in System Settings"
        case .emptyPayload: return "Empty response"
        case .disconnected: return "Disconnected"
        case .connectFailed: return "Bluetooth link failed"
        case .writeFailed: return "Write failed"
        case .rfcommFailed(let code): return "RFCOMM failed (\(code)) — disconnect/reconnect headphones in System Settings"
        case .deviceError(let code): return "Device error \(code)"
        }
    }
}
