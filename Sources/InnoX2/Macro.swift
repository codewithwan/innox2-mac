import Foundation

/// On-mouse macro: `[u16 LE repeatCount]` followed by events, zero-terminated.
///  - key/button: `[code, down<<7 | delay]` when the delay after it is 1...127 ms,
///    otherwise `[code, down<<7, u16 delay]`. Keys use HID usages, mouse buttons F0...F4.
///  - move: `[F9, delay, int8 dx, int8 dy]`, plus `u16 delay` when delay is not 1...127.
struct Macro: Equatable {
    static let slots = 20
    static let maxBytes = 248

    var repeatCount = 1
    var events: [MacroEvent] = []

    var encoded: [UInt8] {
        var o: [UInt8] = [UInt8(repeatCount & 0xFF), UInt8(repeatCount >> 8)]
        for e in events {
            let short = (1...127).contains(e.delay)
            let delayByte = short ? UInt8(e.delay) : 0
            switch e.kind {
            case .key(let u): o += [u, (e.down ? 0x80 : 0) | delayByte]
            case .button(let b): o += [b.rawValue, (e.down ? 0x80 : 0) | delayByte]
            case .move(let dx, let dy): o += [0xF9, delayByte, UInt8(bitPattern: dx), UInt8(bitPattern: dy)]
            }
            if !short { o += [UInt8(e.delay & 0xFF), UInt8((e.delay >> 8) & 0xFF)] }
        }
        // Trailing zeros are implied by the zero-filled buffer, the driver trims them too.
        while o.count > 2, o.last == 0 { o.removeLast() }
        return o
    }

    init(repeatCount: Int = 1, events: [MacroEvent] = []) {
        self.repeatCount = repeatCount
        self.events = events
    }

    init(decoding b: [UInt8]) {
        guard b.count >= 2 else { return }
        repeatCount = b.u16(0)
        var p = 2
        func u16() -> Int { p + 1 < b.count ? b.u16(p) : 0 }
        while p + 1 < b.count, b[p] != 0 {
            let code = b[p]
            var e: MacroEvent
            if code == 0xF9 {
                guard p + 3 < b.count else { break }
                e = MacroEvent(kind: .move(dx: Int8(bitPattern: b[p + 2]), dy: Int8(bitPattern: b[p + 3])), down: false, delay: Int(b[p + 1]))
                p += 4
            } else {
                let kind: MacroEvent.Kind = MacroButton(rawValue: code).map { .button($0) } ?? .key(code)
                e = MacroEvent(kind: kind, down: b[p + 1] & 0x80 != 0, delay: Int(b[p + 1] & 0x7F))
                p += 2
            }
            if e.delay == 0 { e.delay = u16(); p += 2 }
            events.append(e)
        }
    }

    /// Write packets: 56-byte pages, header `16 <slot> <page> <totalLen> <isLast> 00 00 <chk>`.
    func writePackets(slot: Int) -> [[UInt8]] {
        let data = encoded
        let pages = max(1, (data.count + 55) / 56)
        return (0..<pages).map { i in
            let chunk = Array(data[min(data.count, i * 56)..<min(data.count, i * 56 + 56)])
            return Proto.packet([Proto.setMacro, UInt8(slot), UInt8(i), UInt8(data.count), i == pages - 1 ? 1 : 0], data: chunk)
        }
    }
}

enum MacroButton: UInt8, CaseIterable {
    case left = 0xF0, right = 0xF1, middle = 0xF2, back = 0xF3, forward = 0xF4

    var title: String {
        switch self {
        case .left: "Left click"
        case .right: "Right click"
        case .middle: "Middle click"
        case .back: "Back"
        case .forward: "Forward"
        }
    }
}

struct MacroEvent: Equatable, Identifiable {
    enum Kind: Equatable {
        case key(UInt8)
        case button(MacroButton)
        case move(dx: Int8, dy: Int8)
    }

    let id = UUID()
    var kind: Kind
    var down: Bool
    /// Milliseconds to wait after this event.
    var delay: Int

    static func == (a: Self, b: Self) -> Bool { a.kind == b.kind && a.down == b.down && a.delay == b.delay }

    var title: String {
        switch kind {
        case .key(let u): HIDKeys.name(u)
        case .button(let b): b.title
        case .move(let dx, let dy): "Move \(dx), \(dy)"
        }
    }
}

/// Button action that runs a macro. Mode 0 = run `repeatCount` times, 1 = toggle on/off, 2 = repeat while held.
enum MacroMode: UInt8, CaseIterable {
    case once = 0, toggle = 1, hold = 2

    var title: String {
        switch self {
        case .once: "run"
        case .toggle: "toggle loop"
        case .hold: "while held"
        }
    }
}

enum HIDKeys {
    /// macOS virtual key code → HID keyboard usage.
    static let fromMac: [UInt16: UInt8] = [
        0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B, 34: 0x0C, 38: 0x0D,
        40: 0x0E, 37: 0x0F, 46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13, 12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17,
        32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B, 16: 0x1C, 6: 0x1D,
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25, 25: 0x26, 29: 0x27,
        36: 0x28, 53: 0x29, 51: 0x2A, 48: 0x2B, 49: 0x2C, 27: 0x2D, 24: 0x2E, 33: 0x2F, 30: 0x30, 42: 0x31,
        41: 0x33, 39: 0x34, 50: 0x35, 43: 0x36, 47: 0x37, 44: 0x38, 57: 0x39,
        122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41, 101: 0x42,
        109: 0x43, 103: 0x44, 111: 0x45,
        115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E, 124: 0x4F, 123: 0x50, 125: 0x51, 126: 0x52,
        82: 0x62, 83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D, 88: 0x5E, 89: 0x5F, 91: 0x60, 92: 0x61,
        65: 0x63, 67: 0x55, 69: 0x57, 75: 0x54, 76: 0x58, 78: 0x56, 81: 0x67,
        59: 0xE0, 56: 0xE1, 58: 0xE2, 55: 0xE3, 62: 0xE4, 60: 0xE5, 61: 0xE6, 54: 0xE7,
    ]

    static func name(_ u: UInt8) -> String {
        switch u {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(ascii: "A") + u - 0x04))
        case 0x1E...0x26: return String(u - 0x1D)
        case 0x27: return "0"
        case 0x3A...0x45: return "F\(u - 0x39)"
        default: return names[u] ?? String(format: "Key 0x%02X", u)
        }
    }

    private static let names: [UInt8: String] = [
        0x28: "Return", 0x29: "Esc", 0x2A: "Delete", 0x2B: "Tab", 0x2C: "Space", 0x2D: "-", 0x2E: "=",
        0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
        0x39: "Caps Lock", 0x4A: "Home", 0x4B: "Page Up", 0x4C: "Fwd Delete", 0x4D: "End", 0x4E: "Page Down",
        0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
        0xE0: "Control", 0xE1: "Shift", 0xE2: "Option", 0xE3: "Command",
        0xE4: "Right Control", 0xE5: "Right Shift", 0xE6: "Right Option", 0xE7: "Right Command",
    ]
}
