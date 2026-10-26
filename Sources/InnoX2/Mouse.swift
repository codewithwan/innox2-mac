import Foundation
import SwiftUI

/// Talks to the mouse on a serial queue and publishes its state for the UI.
final class Mouse: ObservableObject {
    enum Link: Equatable { case none, dongleAsleep, dongle, wired }

    @Published var link: Link = .none
    @Published var battery: Int?
    @Published var deviceID: Int?
    @Published var firmware: String?
    @Published var options: Options?
    @Published var dpi: DPITable?
    @Published var keys: [[UInt8]] = []
    @Published var macros: [Int: Macro] = [:]
    @Published var busy = false
    @Published var lastError: String?

    private let hid = HIDTransport()
    private let queue = DispatchQueue(label: "innox2.hid")
    private var timer: Timer?
    private var loaded = false
    private var pending: [String: DispatchWorkItem] = [:]

    init() {
        hid.onChange = { [weak self] in self?.deviceChanged() }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.poll() }
        deviceChanged()
    }

    private var isDongle: Bool { hid.productID == Proto.dongleProductID }

    // MARK: - transport

    private func write(_ p: [UInt8]) throws {
        try hid.setFeature(p)
    }

    private func status() throws -> [UInt8] {
        try write(Proto.packet([Proto.rxStatus]))
        return try hid.getFeature()
    }

    /// One request/response. Through the receiver this is: wait until it can relay, select the
    /// mouse, send, wait for the reply flag, release, read.
    private func exchange(_ p: [UInt8], expectEcho: Bool = true) throws -> [UInt8] {
        if !isDongle {
            try write(p)
            usleep(15_000)
            return try hid.getFeature()
        }
        // A sleeping mouse never sees relayed packets; refuse instead of sending into the void.
        if try status()[4] != 0 { throw Self.asleep }
        var reply = [UInt8](repeating: 0, count: 64)
        for _ in 0..<3 {
            for _ in 0..<12 {
                if try status()[5] == 1 { break }
                usleep(15_000)
            }
            try write(Proto.packet([Proto.rxSelect, Proto.mouseRelayTarget]))
            try write(p)
            for _ in 0..<12 {
                usleep(20_000)
                if try status()[0] == 1 { break }
            }
            try write(Proto.packet([Proto.rxRelease]))
            reply = try hid.getFeature()
            if !expectEcho || reply[0] == p[0] { return reply }
            usleep(30_000)
        }
        throw Self.asleep
    }

    private static let asleep = NSError(domain: "InnoX2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mouse did not answer (asleep or out of range?). Move it and try again."])

    /// Writes are not echoed by the mouse, so send them once and do not wait for a reply.
    private func send(_ p: [UInt8]) throws {
        _ = try exchange(p, expectEcho: false)
    }

    private func run(_ work: @escaping () throws -> Void) {
        DispatchQueue.main.async { self.busy = true }
        queue.async {
            var err: String?
            do { try work() } catch { err = "\(error.localizedDescription)" }
            DispatchQueue.main.async {
                self.busy = false
                self.lastError = err
            }
        }
    }

    // MARK: - state

    private func deviceChanged() {
        queue.async { self.loaded = false }
        guard hid.device != nil else {
            link = .none; options = nil; dpi = nil; keys = []; battery = nil
            return
        }
        poll()
    }

    private func poll() {
        guard hid.device != nil else { return }
        queue.async { [self] in
            var newLink: Link = .wired
            var bat: Int?
            if isDongle {
                guard let st = try? status() else { return }
                newLink = st[4] == 0 ? .dongle : .dongleAsleep
                if (1...100).contains(st[2]) { bat = Int(st[2]) }
            }
            DispatchQueue.main.async {
                self.link = newLink
                if bat != nil { self.battery = bat }
            }
            if newLink == .dongleAsleep { return }
            if !loaded {
                loadAll()
            } else if let d = try? exchange(Proto.packet([Proto.getDPI, UInt8(options?.profile ?? 0)])) {
                // Keep the active stage in sync when the DPI button on the mouse is pressed.
                DispatchQueue.main.async {
                    if self.dpi?.current != Int(d[2]) { self.dpi?.current = Int(d[2]) }
                }
            }
        }
    }

    /// Must run on `queue`.
    private func loadAll() {
        do {
            let id = try exchange(Proto.packet([Proto.identify]))
            let fw = try exchange(Proto.packet([Proto.firmware]))
            let opt = Options(raw: try exchange(Proto.packet([Proto.getOption0])))
            let profile = UInt8(opt.profile)
            let d = DPITable(raw: try exchange(Proto.packet([Proto.getDPI, profile])))
            let k = try exchange(Proto.packet([Proto.getKeys, profile]), expectEcho: false)
            loaded = true
            DispatchQueue.main.async {
                self.deviceID = id.u16(1)
                self.firmware = String(format: "%d.%02d", fw[2], fw[1])
                self.options = opt
                self.dpi = d
                self.keys = stride(from: 0, to: 64, by: 4).map { Array(k[$0..<$0 + 4]) }
                self.lastError = nil
            }
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    func reload() {
        run { [self] in
            loaded = false
            loadAll()
        }
    }

    // MARK: - writes

    var pollingRates: [Int] {
        link == .wired ? [125, 250, 500, 1000, 2000, 4000, 8000] : [125, 250, 500, 1000, 2000, 4000]
    }

    /// The UI updates at once; the write goes out after changes settle, so dragging a color
    /// picker or clicking quickly sends one packet instead of dozens.
    func apply(options new: Options) {
        options = new
        debounce("options") { [weak self] in self?.options?.writePacket }
    }

    func apply(dpi new: DPITable) {
        dpi = new
        debounce("dpi") { [weak self] in self?.dpi?.writePacket }
    }

    /// `packet` is evaluated on the main thread when the delay ends, so it sends the latest state.
    private func debounce(_ key: String, _ packet: @escaping () -> [UInt8]?) {
        pending[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let p = packet() else { return }
            self.run { try self.send(p) }
        }
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func setButton(_ b: PhysicalButton, _ action: [UInt8]) {
        guard let profile = options?.profile else { return }
        if keys.count > b.rawValue { keys[b.rawValue] = action }
        run { [self] in
            try send(Proto.packet([Proto.setKey, UInt8(profile), UInt8(b.rawValue)], data: action))
            usleep(100_000)
        }
    }

    func loadMacro(_ slot: Int) {
        run { [self] in
            var buf: [UInt8] = []
            for page in 0..<4 {
                buf += try exchange(Proto.packet([Proto.getMacro, UInt8(slot), UInt8(page)]), expectEcho: false)
            }
            let m = Macro(decoding: buf)
            DispatchQueue.main.async { self.macros[slot] = m }
        }
    }

    func saveMacro(_ slot: Int, _ m: Macro) {
        macros[slot] = m
        run { [self] in
            for p in m.writePackets(slot: slot) { try send(p) }
            usleep(500_000)
        }
    }

    func factoryReset() {
        run { [self] in
            try send(Proto.packet([Proto.factoryReset]))
            usleep(800_000)
            DispatchQueue.main.async { self.macros = [:] }
            loaded = false
            loadAll()
        }
    }
}

extension Mouse {
    /// `InnoX2 --dump`: print what the app reads from the mouse, for debugging without the UI.
    static func dumpAndExit() -> Never {
        let m = Mouse()
        let end = Date().addingTimeInterval(8)
        while m.dpi == nil && m.lastError == nil && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        print("link:", m.link, "battery:", m.battery.map(String.init) ?? "-")
        if let e = m.lastError { print("error:", e) }
        if let id = m.deviceID { print("device id:", String(format: "0x%04X", id), "firmware:", m.firmware ?? "-") }
        if let o = m.options {
            print("polling:", o.pollingRate, "debounce:", o.debounce, "LOD:", o.liftOff == 0 ? "low" : "high",
                  "angle snap:", o.angleSnap, "ripple:", o.rippleControl, "sleep 2.4G/BT:", o.sleep24, o.sleepBT)
        }
        if let d = m.dpi {
            print("dpi:", (0..<d.enabledCount).map { ($0 == d.current ? "*" : "") + "\(d.dpi($0))" }.joined(separator: " "))
        }
        for b in PhysicalButton.allCases where m.keys.count > b.rawValue {
            print("  \(b.title):", ButtonAction.named(m.keys[b.rawValue]).name)
        }
        exit(m.dpi == nil ? 1 : 0)
    }
}
