import AppKit
import SwiftUI
import Combine

/// Menu-bar icon showing battery %, with the quick panel in a popover.
final class StatusBarController {
    private static let autosaveName = "innox2"
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private unowned let mouse: Mouse

    init(mouse: Mouse) {
        self.mouse = mouse
        // New items land at the far left of the menu bar, which on notched MacBooks with a busy
        // menu bar is under the notch. Ask for a spot near the right edge on first run; after
        // that macOS remembers wherever you ⌘-drag it.
        let key = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(360, forKey: key)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = .removalAllowed

        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: MenuBarPanel(close: { [weak self] in
            self?.popover.performClose(nil)
        }).environmentObject(mouse))
        // Without this the popover has no size and opens invisibly.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        cancellable = mouse.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        guard let button = item.button else { return }
        let connected = mouse.link != .none
        let image = NSImage(systemSymbolName: connected ? "computermouse.fill" : "computermouse", accessibilityDescription: "INNO X2")
        image?.isTemplate = true
        button.image = image
        if connected, let b = mouse.battery {
            button.title = " \(b)%"
            button.toolTip = "INNO X2 · \(mouse.statusText) · battery \(b)%"
        } else {
            button.title = ""
            button.toolTip = "INNO X2 · \(mouse.statusText)"
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    /// Right-click: a plain menu with the essentials.
    private func showMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: "INNO X2 · \(mouse.statusText)" + (mouse.battery.map { " · \($0)%" } ?? ""), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open INNO X2…", action: #selector(openWindow), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit INNO X2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
