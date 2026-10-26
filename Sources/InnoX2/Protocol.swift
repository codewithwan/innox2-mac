import Foundation

/// ROYUAN vendor protocol as used by the VortexSeries INNO X2 PRO (device id 0x05E2).
/// Packets are 64 bytes: [0] opcode, [1..6] params, [7] checksum, [8..63] data.
/// GET opcodes are SET | 0x80 and echo the opcode in byte 0 of the reply.
enum Proto {
    static let dongleProductID = 0x402D   // 2.4G receiver
    static let wiredProductID = 0x402A    // USB cable
    static let mouseRelayTarget: UInt8 = 5

    // Receiver-only opcodes
    static let rxStatus: UInt8 = 0xF7     // [2] battery %, [4] 0 = mouse online, [5] 1 = ready to relay, [0] 1 = reply waiting
    static let rxSelect: UInt8 = 0xF6     // [1] relay target
    static let rxRelease: UInt8 = 0xFC

    // Mouse opcodes
    static let identify: UInt8 = 0x8F     // [1..2] device id u16 LE
    static let firmware: UInt8 = 0x80     // [1..2] version u16 LE
    static let getOption0: UInt8 = 0xD3, setOption0: UInt8 = 0x53
    static let getDPI: UInt8 = 0xD4, setDPI: UInt8 = 0x54
    static let getKeys: UInt8 = 0xD0, setKey: UInt8 = 0x50
    static let getMacro: UInt8 = 0x96, setMacro: UInt8 = 0x16  // read pages are 64 bytes, write pages 56
    static let factoryReset: UInt8 = 0x02

    static func packet(_ head: [UInt8], data: [UInt8] = []) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 64)
        for (i, b) in head.prefix(7).enumerated() { p[i] = b }
        for (i, b) in data.prefix(56).enumerated() { p[8 + i] = b }
        return withChecksum(p)
    }

    static func withChecksum(_ p: [UInt8]) -> [UInt8] {
        var p = p
        let sum = p[0..<7].reduce(0) { $0 &+ $1 }
        p[7] = 0xFF &- sum
        return p
    }
}

extension Array where Element == UInt8 {
    func u16(_ i: Int) -> Int { Int(self[i]) | Int(self[i + 1]) << 8 }
    mutating func setU16(_ i: Int, _ v: Int) { self[i] = UInt8(v & 0xFF); self[i + 1] = UInt8((v >> 8) & 0xFF) }
}

/// OPTIONPARAM0 (0xD3/0x53). Kept as the raw reply and written back read-modify-write,
/// the same way the vendor driver does it.
struct Options: Equatable {
    var raw: [UInt8]

    static let pollingCodes: [(hz: Int, code: UInt8)] = [
        (125, 0x08), (250, 0x04), (500, 0x02), (1000, 0x01), (2000, 0x84), (4000, 0x82), (8000, 0x81),
    ]

    var profile: Int { Int(raw[8]) }

    var pollingRate: Int {
        get { Self.pollingCodes.first { $0.code == raw[9] }?.hz ?? 0 }
        set { if let c = Self.pollingCodes.first(where: { $0.hz == newValue })?.code { raw[9] = c } }
    }

    var debounce: Int {
        get { Int(raw[10]) }
        set { raw[10] = UInt8(clamping: newValue) }
    }

    var rippleControl: Bool {
        get { raw[12] & 0x04 != 0 }
        set { if newValue { raw[12] |= 0x04 } else { raw[12] &= ~0x04 } }
    }

    /// Seconds until sleep; 0 = never.
    var sleep24: Int {
        get { raw.u16(44) }
        set { raw.setU16(44, newValue) }
    }

    var sleepBT: Int {
        get { raw.u16(40) }
        set { raw.setU16(40, newValue) }
    }

    /// 0 = low, 1 = high
    var liftOff: Int {
        get { Int(raw[52]) }
        set { raw[52] = UInt8(newValue) }
    }

    var angleSnap: Bool {
        get { raw[53] != 0 }
        set { raw[53] = newValue ? 1 : 0 }
    }

    var writePacket: [UInt8] {
        var p = raw
        p[0] = Proto.setOption0
        return Proto.withChecksum(p)
    }
}

/// OPTIONPARAM1 (0xD4/0x54): 8 DPI stages, X at [8..23], Y at [24..39], RGB colors at [40..63].
/// A stage with value 0 is disabled.
struct DPITable: Equatable {
    static let stageCount = 8
    var raw: [UInt8]

    var current: Int {
        get { Int(raw[2]) }
        set { raw[2] = UInt8(newValue) }
    }

    func dpi(_ i: Int) -> Int { raw.u16(8 + i * 2) }

    mutating func setDPI(_ i: Int, _ v: Int) {
        raw.setU16(8 + i * 2, v)
        raw.setU16(24 + i * 2, v)
    }

    func color(_ i: Int) -> (UInt8, UInt8, UInt8) { (raw[40 + i * 3], raw[41 + i * 3], raw[42 + i * 3]) }

    mutating func setColor(_ i: Int, _ c: (UInt8, UInt8, UInt8)) {
        raw[40 + i * 3] = c.0; raw[41 + i * 3] = c.1; raw[42 + i * 3] = c.2
    }

    /// Enabled stages are the leading non-zero entries.
    var enabledCount: Int {
        (0..<Self.stageCount).first { dpi($0) == 0 } ?? Self.stageCount
    }

    var writePacket: [UInt8] {
        var p = raw
        p[0] = Proto.setDPI
        p[3] = UInt8(Self.stageCount)
        return Proto.withChecksum(p)
    }
}

/// One 4-byte entry of the button map.
struct ButtonAction: Hashable, Identifiable {
    let name: String
    let bytes: [UInt8]
    var id: [UInt8] { bytes }

    static let presets: [ButtonAction] = [
        .init(name: "Left click", bytes: [0x01, 0x00, 0xF0, 0x00]),
        .init(name: "Right click", bytes: [0x01, 0x00, 0xF1, 0x00]),
        .init(name: "Middle click", bytes: [0x01, 0x00, 0xF2, 0x00]),
        .init(name: "Back", bytes: [0x01, 0x00, 0xF3, 0x00]),
        .init(name: "Forward", bytes: [0x01, 0x00, 0xF4, 0x00]),
        .init(name: "Scroll up", bytes: [0x01, 0x00, 0xF5, 0x01]),
        .init(name: "Scroll down", bytes: [0x01, 0x00, 0xF5, 0xFF]),
        .init(name: "DPI cycle", bytes: [0x14, 0x00, 0x00, 0x00]),
        .init(name: "DPI +", bytes: [0x14, 0x00, 0x01, 0x00]),
        .init(name: "DPI −", bytes: [0x14, 0x00, 0x02, 0x00]),
        .init(name: "Play / Pause", bytes: [0x03, 0x00, 0xCD, 0x00]),
        .init(name: "Next track", bytes: [0x03, 0x00, 0xB5, 0x00]),
        .init(name: "Previous track", bytes: [0x03, 0x00, 0xB6, 0x00]),
        .init(name: "Volume up", bytes: [0x03, 0x00, 0xE9, 0x00]),
        .init(name: "Volume down", bytes: [0x03, 0x00, 0xEA, 0x00]),
        .init(name: "Mute", bytes: [0x03, 0x00, 0xE2, 0x00]),
        .init(name: "Copy (⌘C)", bytes: [0x00, 0xE3, 0x06, 0x00]),
        .init(name: "Paste (⌘V)", bytes: [0x00, 0xE3, 0x19, 0x00]),
        .init(name: "Mission Control (⌃↑)", bytes: [0x00, 0xE0, 0x52, 0x00]),
        .init(name: "Desktop left (⌃←)", bytes: [0x00, 0xE0, 0x50, 0x00]),
        .init(name: "Desktop right (⌃→)", bytes: [0x00, 0xE0, 0x4F, 0x00]),
        .init(name: "Disabled", bytes: [0x00, 0x00, 0x00, 0x00]),
    ]

    static func macro(_ slot: Int, _ mode: MacroMode) -> ButtonAction {
        .init(name: "Macro \(slot + 1) (\(mode.title))", bytes: [0x09, mode.rawValue, UInt8(slot), 0x00])
    }

    static let macros: [ButtonAction] = MacroMode.allCases.flatMap { m in (0..<Macro.slots).map { macro($0, m) } }

    static func named(_ bytes: [UInt8]) -> ButtonAction {
        if bytes.count == 4, bytes[0] == 0x09, let m = MacroMode(rawValue: bytes[1]), Int(bytes[2]) < Macro.slots {
            return macro(Int(bytes[2]), m)
        }
        return presets.first { $0.bytes == bytes }
            ?? .init(name: "Custom " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "), bytes: bytes)
    }
}

/// Physical buttons and their slot in the 16-entry map.
enum PhysicalButton: Int, CaseIterable, Identifiable {
    case left = 0, right = 1, middle = 2, forward = 3, back = 4, dpi = 6
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .left: "Left button"
        case .right: "Right button"
        case .middle: "Wheel click"
        case .forward: "Side front"
        case .back: "Side rear"
        case .dpi: "DPI button"
        }
    }

    var factoryDefault: [UInt8] {
        switch self {
        case .left: [0x01, 0x00, 0xF0, 0x00]
        case .right: [0x01, 0x00, 0xF1, 0x00]
        case .middle: [0x01, 0x00, 0xF2, 0x00]
        case .forward: [0x01, 0x00, 0xF4, 0x00]
        case .back: [0x01, 0x00, 0xF3, 0x00]
        case .dpi: [0x14, 0x00, 0x00, 0x00]
        }
    }
}
