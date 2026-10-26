import SwiftUI
import AppKit

/// The panel that drops down from the menu-bar icon: battery, DPI stage, polling rate, shortcuts.
struct MenuBarPanel: View {
    @EnvironmentObject var mouse: Mouse
    var close: () -> Void = {}
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if mouse.link == .none {
                Text("Plug in the 2.4G receiver or the USB cable.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if mouse.link == .dongleAsleep {
                Label("Mouse is asleep, move it to wake it.", systemImage: "moon.zzz")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if mouse.link != .none, let d = mouse.dpi {
                VStack(alignment: .leading, spacing: 6) {
                    PanelLabel("DPI")
                    StagePills(table: d) { i in var n = d; n.current = i; mouse.apply(dpi: n) }
                }
                .disabled(mouse.link == .dongleAsleep)
            }

            if mouse.link != .none, let o = mouse.options {
                VStack(alignment: .leading, spacing: 6) {
                    PanelLabel("Polling rate")
                    Picker("", selection: Binding(get: { o.pollingRate }, set: { v in var n = o; n.pollingRate = v; mouse.apply(options: n) })) {
                        ForEach(mouse.pollingRates, id: \.self) { Text(rateLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .disabled(mouse.link == .dongleAsleep)
            }

            Divider()

            VStack(spacing: 2) {
                PanelButton(title: "Open INNO X2…", symbol: "slider.horizontal.3") {
                    close()
                    NotificationCenter.default.post(name: .openMainWindow, object: nil)
                }
                HStack {
                    Label("Launch at login", systemImage: "power")
                    Spacer()
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { v in LaunchAtLogin.set(v); launchAtLogin = LaunchAtLogin.isEnabled }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                PanelButton(title: "Quit", symbol: "xmark.circle") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                Image(systemName: "computermouse.fill").font(.title3)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("INNO X2 PRO").font(.headline)
                Text(mouse.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let b = mouse.battery, mouse.link != .none {
                BatteryBadge(percent: b)
            }
        }
    }
}

func rateLabel(_ hz: Int) -> String { hz >= 1000 ? "\(hz / 1000)K" : "\(hz)" }

struct PanelLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}

struct BatteryBadge: View {
    let percent: Int

    var color: Color { percent <= 15 ? .red : percent <= 30 ? .orange : .green }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: percent > 80 ? "battery.100" : percent > 55 ? "battery.75" : percent > 30 ? "battery.50" : percent > 10 ? "battery.25" : "battery.0")
                .foregroundStyle(color)
            Text("\(percent)%").font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
        }
    }
}

/// Clickable DPI stage chips, the active one filled in its stage color.
struct StagePills: View {
    let table: DPITable
    var select: (Int) -> Void

    var body: some View {
        let n = table.enabledCount
        HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { i in
                let active = table.current == i
                Button { select(i) } label: {
                    Text(verbatim: table.dpi(i) >= 10000 ? "\(table.dpi(i) / 1000)K" : "\(table.dpi(i))")
                        .font(.callout.weight(active ? .semibold : .regular)).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .foregroundStyle(active ? .white : .primary)
                        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PanelButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
