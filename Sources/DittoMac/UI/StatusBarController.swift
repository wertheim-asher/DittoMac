import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    var onOpenPopup: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "DittoMac")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            onOpenPopup?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Clipboard History", action: #selector(openPopupFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferencesFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DittoMac", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach the menu after it's shown once so left-click keeps opening the popup instead.
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func openPopupFromMenu() { onOpenPopup?() }
    @objc private func openPreferencesFromMenu() { onOpenPreferences?() }
    @objc private func quitFromMenu() { onQuit?() }

    var buttonBounds: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
