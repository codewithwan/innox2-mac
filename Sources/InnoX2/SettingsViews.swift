import SwiftUI
import AppKit

/// Form row title with a smaller explanation underneath.
struct RowTitle: View {
    let title: String
    let detail: String
    init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - DPI

struct DPISection: View {
    @EnvironmentObject var mouse: Mouse

    var body: some View {
        if let d = mouse.dpi {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(d.dpi(d.current))")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("DPI").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Stage \(d.current + 1) of \(d.enabledCount)").foregroundStyle(.secondary)
                    }
                    StagePills(table: d) { i in var n = d; n.current = i; mouse.apply(dpi: n) }
                }
                .padding(.vertical, 4)
            } footer: {
                Footer("The DPI button on the mouse cycles through these stages.")
            }

            Section {
                ForEach(0..<d.enabledCount, id: \.self) { i in
                    DPIRow(index: i, table: d)
                }
                HStack(spacing: 8) {
                    Button {
                        var n = d
                        let last = n.dpi(n.enabledCount - 1)
                        n.setDPI(n.enabledCount, min(26000, last + 800))
                        mouse.apply(dpi: n)
                    } label: { Label("Add stage", systemImage: "plus") }
                    .disabled(d.enabledCount >= DPITable.stageCount)
                    Button {
                        var n = d
                        let last = n.enabledCount - 1
                        n.setDPI(last, 0)
                        if n.current >= last { n.current = last - 1 }
                        mouse.apply(dpi: n)
                    } label: { Label("Remove last", systemImage: "minus") }
                    .disabled(d.enabledCount <= 1)
                    Spacer()
                }
            } header: {
                Text("Stages")
            } footer: {
                Footer("50 – 26000 DPI in steps of 50. The color is what the mouse's indicator shows for that stage.")
            }
        }
    }
}

struct DPIRow: View {
    @EnvironmentObject var mouse: Mouse
    let index: Int
    let table: DPITable
    @State private var slider: Double = 800
    @State private var text = ""

    var value: Int { table.dpi(index) }
    var active: Bool { table.current == index }

    var body: some View {
        VStack {
        HStack(spacing: 12) {
            Button {
                var n = table; n.current = index; mouse.apply(dpi: n)
            } label: {
                Text("\(index + 1)")
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(active ? .white : .primary)
                    .background(Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Make stage \(index + 1) active")

            Slider(value: $slider, in: 50...26000, step: 50) {
                Text("Stage \(index + 1)")
            } onEditingChanged: { editing in
                if !editing { commit(Int(slider)) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit { if let v = Int(text) { commit(v) } else { sync() } }
            ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
        }
        }
        .onAppear(perform: sync)
        .onChange(of: value) { sync() }
    }

    func commit(_ v: Int) {
        var n = table
        n.setDPI(index, max(50, min(26000, (v / 50) * 50)))
        mouse.apply(dpi: n)
        sync()
    }

    func sync() {
        slider = Double(value)
        text = "\(value)"
    }

    var colorBinding: Binding<Color> {
        Binding(get: {
            let c = table.color(index)
            return Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
        }, set: { col in
            guard let ns = NSColor(col).usingColorSpace(.sRGB) else { return }
            var n = table
            n.setColor(index, (UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255)))
            mouse.apply(dpi: n)
        })
    }
}

// MARK: - Performance

struct PerformanceSection: View {
    @EnvironmentObject var mouse: Mouse

    var body: some View {
        if let o = mouse.options {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    RowTitle("Polling rate", "How often the mouse reports to the Mac. Higher is smoother but uses more battery.")
                    Picker("", selection: bind(o, \.pollingRate)) {
                        ForEach(mouse.pollingRates, id: \.self) { Text(rateLabel($0) + " Hz").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
                if mouse.link != .wired {
                    Text("8K Hz is only available with the USB cable.").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Report rate")
            }

            Section("Sensor") {
                Picker(selection: bind(o, \.liftOff)) {
                    Text("Low").tag(0)
                    Text("High").tag(1)
                } label: {
                    RowTitle("Lift-off distance", "Height at which the sensor stops tracking when you lift the mouse.")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: bind(o, \.angleSnap)) {
                    RowTitle("Angle snapping", "Straightens slightly wobbly horizontal and vertical movements.")
                }
                Toggle(isOn: bind(o, \.rippleControl)) {
                    RowTitle("Ripple control", "Smooths sensor jitter at very high DPI, adds a little latency.")
                }
            }

            Section("Buttons") {
                Stepper(value: bind(o, \.debounce), in: 0...20) {
                    RowTitle("Debounce time: \(o.debounce) ms", "Raise it if a click sometimes registers as a double click.")
                }
            }
        }
    }

    func bind<T>(_ o: Options, _ kp: WritableKeyPath<Options, T>) -> Binding<T> {
        Binding(get: { o[keyPath: kp] }, set: { v in var n = o; n[keyPath: kp] = v; mouse.apply(options: n) })
    }
}

// MARK: - Power

struct PowerSection: View {
    @EnvironmentObject var mouse: Mouse
    static let choices = [10, 20, 30, 60, 120, 300, 600, 1800, 3600, 0]

    var body: some View {
        Section("Battery") {
            if let b = mouse.battery {
                HStack(spacing: 14) {
                    Image(systemName: mouse.batterySymbol)
                        .font(.system(size: 30))
                        .foregroundStyle(mouse.batteryColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(b)%").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(mouse.batteryColor.gradient).frame(width: g.size.width * CGFloat(b) / 100)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text(mouse.link == .wired ? "Charging over USB" : "Unknown").foregroundStyle(.secondary)
            }
        }
        if let o = mouse.options {
            Section {
                Picker("Sleep after (2.4G)", selection: bind(o, \.sleep24)) { items(o.sleep24) }
                Picker("Sleep after (Bluetooth)", selection: bind(o, \.sleepBT)) { items(o.sleepBT) }
            } header: {
                Text("Sleep")
            } footer: {
                Footer("A short sleep timer saves battery; the first movement after it wakes the mouse with a small delay.")
            }
        }
    }

    @ViewBuilder func items(_ current: Int) -> some View {
        ForEach(Self.choices.contains(current) ? Self.choices : Self.choices + [current], id: \.self) {
            Text(label($0)).tag($0)
        }
    }

    func label(_ s: Int) -> String {
        s == 0 ? "Never (drains battery)" : s < 60 ? "\(s) seconds" : s == 60 ? "1 minute" : "\(s / 60) minutes"
    }

    func bind(_ o: Options, _ kp: WritableKeyPath<Options, Int>) -> Binding<Int> {
        Binding(get: { o[keyPath: kp] }, set: { v in var n = o; n[keyPath: kp] = v; mouse.apply(options: n) })
    }
}

// MARK: - Buttons

struct ButtonsSection: View {
    @EnvironmentObject var mouse: Mouse
    @State private var confirmRestore = false

    var body: some View {
        Section {
            ForEach(PhysicalButton.allCases) { b in
                if mouse.keys.count > b.rawValue {
                    let bytes = mouse.keys[b.rawValue]
                    let current = ButtonAction.named(bytes)
                    let mode = macroMode(bytes)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(selection: Binding(get: { current }, set: { mouse.setButton(b, $0.bytes) })) {
                            ForEach(options(current)) { Text($0.name).tag($0) }
                            Divider()
                            ForEach(0..<Macro.slots, id: \.self) { s in
                                Text("Macro \(s + 1)").tag(ButtonAction.macro(s, mode ?? .once))
                            }
                        } label: {
                            Label(b.title, systemImage: b.symbol)
                        }
                        if let mode {
                            Picker("Mode", selection: Binding(get: { mode }, set: { m in
                                mouse.setButton(b, [0x09, m.rawValue, bytes[2], 0x00])
                            })) {
                                Text("Run (repeat count)").tag(MacroMode.once)
                                Text("Toggle loop").tag(MacroMode.toggle)
                                Text("While held").tag(MacroMode.hold)
                            }
                            .pickerStyle(.segmented)
                            .padding(.leading, 28)
                        }
                    }
                }
            }
        } header: {
            Text("Button assignments")
        } footer: {
            Footer("Keep at least one button on Left click, or you'll need the cable / factory reset to recover.")
        }

        Section {
            Button("Restore default buttons…") { confirmRestore = true }
                .confirmationDialog("Put every button back to its factory action?", isPresented: $confirmRestore) {
                    Button("Restore") { for b in PhysicalButton.allCases { mouse.setButton(b, b.factoryDefault) } }
                }
        }
    }

    func options(_ current: ButtonAction) -> [ButtonAction] {
        ButtonAction.presets.contains(current) || macroMode(current.bytes) != nil
            ? ButtonAction.presets : ButtonAction.presets + [current]
    }

    func macroMode(_ bytes: [UInt8]) -> MacroMode? {
        bytes.count == 4 && bytes[0] == 0x09 ? MacroMode(rawValue: bytes[1]) : nil
    }
}

extension PhysicalButton {
    var symbol: String {
        switch self {
        case .left: "l.square"
        case .right: "r.square"
        case .middle: "circle.circle"
        case .forward: "arrow.right.square"
        case .back: "arrow.left.square"
        case .dpi: "scope"
        }
    }
}

// MARK: - Device

struct DeviceSection: View {
    @EnvironmentObject var mouse: Mouse
    @State private var confirmReset = false

    var body: some View {
        Section("Device") {
            LabeledContent("Model", value: "VortexSeries INNO X2 PRO")
            LabeledContent("Connection", value: mouse.statusText)
            if let id = mouse.deviceID { LabeledContent("Device ID", value: String(format: "0x%04X", id)) }
            if let fw = mouse.firmware { LabeledContent("Firmware", value: fw) }
        }
        Section {
            Button(role: .destructive) { confirmReset = true } label: {
                Text("Factory reset…").foregroundStyle(.red)
            }
                .confirmationDialog("Reset all mouse settings, buttons and macros to factory defaults?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { mouse.factoryReset() }
                }
        }
    }
}

/// Section footer, left-aligned like System Settings (grouped forms right-align it otherwise).
struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
