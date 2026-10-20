import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    private let store: ClipboardStore

    convenience init(
        store: ClipboardStore, syncService: SyncService,
        onHotKeysChanged: @escaping () -> Void, onHotKeyRecordingChanged: @escaping (Bool) -> Void
    ) {
        let view = PreferencesView(
            store: store, syncService: syncService,
            onHotKeysChanged: onHotKeysChanged, onHotKeyRecordingChanged: onHotKeyRecordingChanged
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "DittoMac Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        self.init(window: window, store: store)
    }

    private init(window: NSWindow, store: ClipboardStore) {
        self.store = store
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        // Reset to the General tab (see ClipboardStore.preferencesOpenCount) without rebuilding
        // the whole SwiftUI hierarchy — recreating the NSHostingController on every open was the
        // main source of visible lag when opening this window.
        store.notifyPreferencesWillShow()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
