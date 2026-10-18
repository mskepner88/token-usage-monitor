import AppKit
import SwiftUI
import TUMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "chart.bar.fill",
                accessibilityDescription: "Token Usage Monitor"
            )
            button.image?.isTemplate = true
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Token Usage Monitor"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let hosting = NSHostingController(
            rootView: ContentView(
                store: store,
                onOpenSettings: { [weak self] in
                    self?.showSettings()
                },
                onContentHeight: { [weak self] height in
                    let fitted = max(180, min(height, 920))
                    self?.popover?.contentSize = NSSize(width: 760, height: fitted)
                }
            )
        )
        hosting.sizingOptions = .preferredContentSize

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 760, height: 420)
        popover.contentViewController = hosting
        self.popover = popover

        store.onDashboardChange = { [weak self] dashboard in
            self?.updateStatusTitle(from: dashboard)
        }

        Task {
            await store.refresh()
            updateStatusTitle(from: store.dashboard)
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(relativeTo: button)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task { await store.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open TUM", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Share snapshot", action: #selector(shareFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TUM", action: #selector(quitFromMenu), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openFromMenu() {
        guard let button = statusItem?.button, let popover else { return }
        Task { await store.refresh() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func shareFromMenu() {
        store.shareSnapshot()
    }

    @objc private func quitFromMenu() {
        store.quit()
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TUM Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 720))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusTitle(from dashboard: UsageDashboard) {
        guard let button = statusItem?.button else { return }
        // Icon-only menu bar item; put the summary in the hover tooltip.
        let live = dashboard.providers.filter { $0.state == .live && !$0.meters.isEmpty }
        guard let worst = live.min(by: {
            ($0.meters.map(\.percentLeft).min() ?? 100) < ($1.meters.map(\.percentLeft).min() ?? 100)
        }) else {
            button.toolTip = "Token Usage Monitor"
            return
        }
        let pct = worst.meters.map(\.percentLeft).min() ?? 100
        button.toolTip = "TUM — \(worst.id.displayName) \(pct)% left"
    }
}
