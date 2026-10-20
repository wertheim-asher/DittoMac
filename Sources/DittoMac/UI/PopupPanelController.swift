import AppKit
import SwiftUI

final class PopupPanelController: NSObject {
    private let panel = PopupPanel()
    private let store: ClipboardStore
    private let pasteService: PasteService
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?

    var anchorRect: (() -> NSRect?)?
    var onOpenPreferences: (() -> Void)?

    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125

    init(store: ClipboardStore, pasteService: PasteService) {
        self.store = store
        self.pasteService = pasteService
        super.init()

        let view = PopupView(
            store: store,
            onPasteSingle: { [weak self] item in self?.pasteAndHide([item]) },
            onPasteMulti: { [weak self] items in self?.pasteAndHide(items) },
            onCopySelection: { [weak self] items in self?.copyAndHide(items) },
            onDismiss: { [weak self] in self?.hide() },
            onOpenPreferences: { [weak self] in
                self?.hide()
                self?.onOpenPreferences?()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    /// `centeredOnActiveScreen`: true for the global hotkey (the user could be anywhere,
    /// possibly a different display than the menu bar — Ditto and similar launchers center on
    /// wherever you currently are rather than pinning to a fixed menu-bar-relative spot), false
    /// for clicking the status item itself (where anchoring under the icon you just clicked is
    /// the expected response).
    func toggle(centeredOnActiveScreen: Bool = false) {
        if panel.isVisible { hide() } else { show(centeredOnActiveScreen: centeredOnActiveScreen) }
    }

    func show(centeredOnActiveScreen: Bool = false) {
        pasteService.rememberFrontmostApp()
        store.searchText = ""
        store.refresh()
        store.notifyPopupWillShow()

        if centeredOnActiveScreen, let screen = screenContainingMouse() {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2)
            panel.setFrameOrigin(origin)
        } else if let anchor = anchorRect?() {
            let panelSize = panel.frame.size
            var origin = NSPoint(x: anchor.midX - panelSize.width / 2, y: anchor.minY - panelSize.height - 4)
            if let screen = NSScreen.main?.visibleFrame {
                origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - panelSize.width - 8))
                origin.y = max(screen.minY + 8, origin.y)
            }
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.midY - panel.frame.height / 2)
            panel.setFrameOrigin(origin)
        }

        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
    }

    private func pasteAndHide(_ items: [ClipItem]) {
        hide()
        pasteService.pasteCombined(items)
    }

    private func copyAndHide(_ items: [ClipItem]) {
        hide()
        pasteService.copyToClipboard(items)
    }

    private func installMonitors() {
        removeMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }

        // A *global* monitor only sees clicks that land in other applications' windows — clicks
        // inside our own popup, its settings popover, or the Preferences window never reach it.
        // That makes it the reliable signal for "user clicked truly outside" without needing to
        // reason about which of our own child windows/popovers currently holds key status.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    /// Returns the event to pass it through untouched, or nil to consume it.
    ///
    /// The search field holds keyboard focus by default (set in PopupView), so ordinary typing
    /// — including the very first keystroke — is handled natively by AppKit with nothing
    /// intercepted here. We only need to grab arrow keys, since the field would otherwise just
    /// move its text cursor. Enter/⌘C/Esc are all handled via SwiftUI `.keyboardShortcut`s in
    /// PopupView instead of here — going through a raw local monitor for them produced system
    /// beeps (the focused text field's own built-in handling firing alongside ours).
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }

        if event.keyCode == Self.upArrowKeyCode {
            if event.modifierFlags.contains(.shift) {
                store.extendSelection(by: -1)
            } else {
                store.moveSelection(by: -1)
            }
            return nil
        }

        if event.keyCode == Self.downArrowKeyCode {
            if event.modifierFlags.contains(.shift) {
                store.extendSelection(by: 1)
            } else {
                store.moveSelection(by: 1)
            }
            return nil
        }

        return event
    }
}
