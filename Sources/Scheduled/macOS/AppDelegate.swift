import AppKit
import SwiftUI

/// Menu-bar controller. Owns the status item, the floating capture panel, the
/// settings window, and the global hotkey.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var capturePanel: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar / accessory app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        GlobalHotKey.shared.onPress = { [weak self] in
            DispatchQueue.main.async { self?.toggleCapture() }
        }
        GlobalHotKey.shared.register() // ⌘⌃J

        // First-run: if no key configured, nudge the user to settings.
        if !state.hasAPIKey {
            openSettings()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.clock",
                                   accessibilityDescription: "Scheduled")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { toggleCapture(); return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggleCapture()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Schedule…  (⌘⌃J)",
                     action: #selector(toggleCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Plan My Day", action: #selector(planMyDay), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Scheduled", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // reset so left-click reverts to capture toggle
    }

    // MARK: - Capture panel

    @objc private func toggleCapture() {
        if let panel = capturePanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showCapture()
    }

    private func showCapture() {
        let panel = capturePanel ?? makeCapturePanel()
        capturePanel = panel

        // Center on the screen with the mouse.
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: screen.frame.midY + screen.frame.height * 0.12
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeCapturePanel() -> NSWindow {
        let view = CaptureView(state: state) { [weak self] in
            self?.capturePanel?.orderOut(nil)
        }
        let hosting = NSHostingView(rootView: view)

        // A standard resizable window: supports drag-resize, minimize, and the
        // green full-screen / zoom (fit-to-size) button. Full screen requires a
        // normal window level, so we no longer float above other apps.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scheduled"
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.contentMinSize = NSSize(width: 380, height: 200)
        window.setContentSize(NSSize(width: 460, height: 300))
        return window
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(state: state) { [weak self] in
            self?.settingsWindow?.orderOut(nil)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [.fullScreenPrimary]
        window.title = "Scheduled Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func planMyDay() {
        showCapture() // reveal the panel so the result shows in its log
        Task { await state.planToday() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
