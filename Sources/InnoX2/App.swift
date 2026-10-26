import SwiftUI
import AppKit
import ServiceManagement

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump") { Mouse.dumpAndExit() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(to: CommandLine.arguments[i + 1])
        }
        InnoX2App.main()
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("innox2.openMainWindow")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let mouse = Mouse()
    private var statusBar: StatusBarController?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController(mouse: mouse)
        NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.showMainWindow()
        }
        // Started by hand: show the window. Started at login: stay quietly in the menu bar.
        if !LaunchAtLogin.isEnabled { showMainWindow() }
    }

    /// Double-clicking the app while it already runs in the menu bar opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func showMainWindow() {
        if window == nil {
            let host = NSHostingController(rootView: ContentView().environmentObject(mouse).frame(minWidth: 760, minHeight: 560))
            host.sceneBridgingOptions = .all
            let w = NSWindow(contentViewController: host)
            w.title = "INNO X2"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 860, height: 640))
            if !w.setFrameUsingName("main") { w.center() }
            w.setFrameAutosaveName("main")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Everything lives in AppDelegate (status item + window); SwiftUI only needs a scene to exist.
struct InnoX2App: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login: \(error)")
        }
    }
}

extension Mouse {
    var statusText: String {
        switch link {
        case .none: "Receiver not connected"
        case .dongleAsleep: "2.4G · asleep"
        case .dongle: "2.4G wireless"
        case .wired: "USB cable"
        }
    }

    var batteryColor: Color {
        guard let b = battery else { return .secondary }
        return b <= 15 ? .red : b <= 30 ? .orange : .green
    }

    var batterySymbol: String {
        guard let b = battery else { return "battery.0" }
        return b > 80 ? "battery.100" : b > 55 ? "battery.75" : b > 30 ? "battery.50" : b > 10 ? "battery.25" : "battery.0"
    }
}
