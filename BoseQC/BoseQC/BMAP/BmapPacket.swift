import Foundation

enum BmapOperator: UInt8 {
    case set = 0
    case get = 1
    case setGet = 2
    case status = 3
    case error = 4
    case start = 5
    case result = 6
    case processing = 7
}

enum BmapBlock: UInt8 {
    case settings = 0x01
    case status = 0x02
    case audioModes = 0x1F
}

struct BmapPacket: Equatable {
    var block: UInt8
    var function: UInt8
    var device: UInt8
    var port: UInt8
    var op: UInt8
    var payload: Data

    /// ANChor packs op in low nibble with device/port 0 → byte2 == op.
    var headerByte2: UInt8 {
        ((device & 0x03) << 6) | ((port & 0x03) << 4) | (op & 0x0F)
    }

    func encode() -> Data {
        var data = Data(capacity: 4 + payload.count)
        data.append(block)
        data.append(function)
        data.append(headerByte2)
        data.append(UInt8(min(payload.count, 255)))
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) -> BmapPacket? {
        guard data.count >= 4 else { return nil }
        let length = Int(data[3])
        guard data.count >= 4 + length else { return nil }
        let byte2 = data[2]
        return BmapPacket(
            block: data[0],
            function: data[1],
            device: (byte2 >> 6) & 0x03,
            port: (byte2 >> 4) & 0x03,
            op: byte2 & 0x0F,
            payload: data.subdata(in: 4..<(4 + length))
        )
    }

    static func get(block: BmapBlock, function: UInt8, payload: Data = Data()) -> BmapPacket {
        BmapPacket(block: block.rawValue, function: function, device: 0, port: 0, op: BmapOperator.get.rawValue, payload: payload)
    }

    static func start(block: BmapBlock, function: UInt8, payload: Data) -> BmapPacket {
        BmapPacket(block: block.rawValue, function: function, device: 0, port: 0, op: BmapOperator.start.rawValue, payload: payload)
    }
}

enum BmapCommands {
    static var queryBattery: BmapPacket { .get(block: .status, function: 0x02) }
    static var queryName: BmapPacket { .get(block: .settings, function: 0x02) }
    static var queryCurrentMode: BmapPacket { .get(block: .audioModes, function: 0x03) }
    static var queryCapabilities: BmapPacket { .get(block: .audioModes, function: 0x02) }

    static func setMode(index: UInt8, voicePrompt: Bool = false) -> BmapPacket {
        .start(block: .audioModes, function: 0x03, payload: Data([index, voicePrompt ? 1 : 0]))
    }

    static func queryModeConfig(index: UInt8) -> BmapPacket {
        .get(block: .audioModes, function: 0x06, payload: Data([index]))
    }
}
