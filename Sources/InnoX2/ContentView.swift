import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    case dpi, performance, buttons, macros, device
    var id: Self { self }

    var title: String {
        switch self {
        case .dpi: "DPI"
        case .performance: "Performance"
        case .buttons: "Buttons"
        case .macros: "Macros"
        case .device: "Power & Device"
        }
    }

    var symbol: String {
        switch self {
        case .dpi: "scope"
        case .performance: "bolt.fill"
        case .buttons: "computermouse.fill"
        case .macros: "keyboard.fill"
        case .device: "battery.75"
        }
    }

    var tint: Color {
        switch self {
        case .dpi: .blue
        case .performance: .orange
        case .buttons: .purple
        case .macros: .pink
        case .device: .green
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var mouse: Mouse
    @State var page: Page? = .dpi

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label {
                    Text(p.title)
                } icon: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.tint.gradient))
                }
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { DeviceCard().padding(10) }
        } detail: {
            detail
                .navigationTitle(page?.title ?? "INNO X2")
                .toolbar {
                    ToolbarItem {
                        if mouse.busy { ProgressView().controlSize(.small) }
                    }
                    ToolbarItem {
                        Button { mouse.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                            .help("Read all settings from the mouse again")
                            .disabled(mouse.link == .none)
                    }
                }
        }
    }

    @ViewBuilder var detail: some View {
        if mouse.options == nil || mouse.dpi == nil {
            EmptyState()
        } else {
            VStack(spacing: 0) {
                if mouse.link == .dongleAsleep {
                    Banner(symbol: "moon.zzz.fill", text: "The mouse is asleep. Move it to wake it up before changing settings.", color: .orange)
                }
                if let e = mouse.lastError {
                    Banner(symbol: "exclamationmark.triangle.fill", text: e, color: .red)
                }
                Group {
                    switch page ?? .dpi {
                    case .dpi: Form { DPISection() }.formStyle(.grouped)
                    case .performance: Form { PerformanceSection() }.formStyle(.grouped)
                    case .buttons: Form { ButtonsSection() }.formStyle(.grouped)
                    case .macros: MacrosView()
                    case .device: Form { PowerSection(); DeviceSection() }.formStyle(.grouped)
                    }
                }
                .disabled(mouse.link == .dongleAsleep || mouse.link == .none)
            }
        }
    }
}

struct Banner: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(color.opacity(0.12))
    }
}

struct EmptyState: View {
    @EnvironmentObject var mouse: Mouse

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: mouse.link == .none ? "cable.connector.slash" : "computermouse")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(mouse.link == .none ? "No mouse found" : "Waiting for the mouse…")
                .font(.title3.weight(.semibold))
            Text(mouse.link == .none ? "Plug in the 2.4G receiver or the USB cable."
                 : "Move the mouse to wake it up.")
                .foregroundStyle(.secondary)
            if mouse.link != .none { ProgressView().controlSize(.small).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sidebar footer: connection + battery at a glance.
struct DeviceCard: View {
    @EnvironmentObject var mouse: Mouse

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse.fill")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text("INNO X2 PRO").font(.callout.weight(.semibold))
                HStack(spacing: 4) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(mouse.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let b = mouse.battery, mouse.link != .none {
                VStack(spacing: 1) {
                    Image(systemName: mouse.batterySymbol).foregroundStyle(mouse.batteryColor)
                    Text("\(b)%").font(.caption.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
    }

    var dotColor: Color {
        switch mouse.link {
        case .none: .red
        case .dongleAsleep: .orange
        case .dongle, .wired: .green
        }
    }
}
