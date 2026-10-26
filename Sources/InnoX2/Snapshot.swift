import SwiftUI
import AppKit

/// `InnoX2 --snapshot <dir>`: render every page and the menu-bar panel to PNGs (debug aid).
enum Snapshot {
    static func run(to dir: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let mouse = Mouse()
        let end = Date().addingTimeInterval(10)
        while mouse.dpi == nil && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if mouse.dpi != nil { mouse.loadMacro(0) } else { fillSample(mouse) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for page in Page.allCases {
                render(ContentView(page: page).environmentObject(mouse), size: NSSize(width: 860, height: 640),
                       appearance: appearance, to: "\(dir)/\(page.rawValue)\(dark ? "-dark" : "").png")
            }
            render(MenuBarPanel().environmentObject(mouse).fixedSize(), size: NSSize(width: 300, height: 360),
                   appearance: appearance, to: "\(dir)/menubar\(dark ? "-dark" : "").png")
        }
        exit(0)
    }

    /// Values read from a real INNO X2 PRO, used when the mouse is asleep.
    static func fillSample(_ m: Mouse) {
        func hex(_ s: String) -> [UInt8] {
            var b = stride(from: 0, to: s.count, by: 2).map { i -> UInt8 in
                let a = s.index(s.startIndex, offsetBy: i); return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)!
            }
            b += [UInt8](repeating: 0, count: 64 - b.count)
            return b
        }
        m.link = .dongle
        m.battery = 57
        m.deviceID = 0x05E2
        m.firmware = "1.01"
        m.options = Options(raw: hex("d3000000000000002c000101000000000a0101000000000000000303040700000000000000000000000014000000140000000000646400"))
        m.dpi = DPITable(raw: hex("d40001080000002b2003400600000000000000000000000020034006000000000000000000000000ff000000ff000000ffffff00ff00ff00ffffffffffff8000"))
        m.keys = [[1, 0, 0xF0, 0], [1, 0, 0xF1, 0], [1, 0, 0xF2, 0], [1, 0, 0xF4, 0], [1, 0, 0xF3, 0], [0x0A, 5, 0, 0], [0x09, 2, 0, 0]]
        m.macros[0] = Macro(repeatCount: 1, events: [
            MacroEvent(kind: .key(0xE3), down: true, delay: 15), MacroEvent(kind: .key(0x06), down: true, delay: 40),
            MacroEvent(kind: .key(0x06), down: false, delay: 15), MacroEvent(kind: .key(0xE3), down: false, delay: 20),
        ])
    }

    static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance?, to path: String) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = appearance
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let frame = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: frame) else { return }
        host.cacheDisplay(in: frame, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}
