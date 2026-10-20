import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var pasteService: PasteService!
    private var syncService: SyncService!
    private var hotKeyManager: HotKeyManager!
    private var statusBar: StatusBarController!
    private var popupController: PopupPanelController!
    private var preferencesController: PreferencesWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardStore()
        monitor = ClipboardMonitor(store: store)
        monitor.start()

        pasteService = PasteService(monitor: monitor, store: store)
        syncService = SyncService(store: store)

        popupController = PopupPanelController(store: store, pasteService: pasteService)

        statusBar = StatusBarController()
        statusBar.onOpenPopup = { [weak self] in self?.popupController.toggle() }
        statusBar.onOpenPreferences = { [weak self] in self?.preferencesController.show() }
        statusBar.onQuit = { NSApp.terminate(nil) }
        popupController.anchorRect = { [weak self] in self?.statusBar.buttonBounds }

        preferencesController = PreferencesWindowController(
            store: store, syncService: syncService,
            onHotKeysChanged: { [weak self] in self?.registerHotKeys() },
            onHotKeyRecordingChanged: { [weak self] isRecording in
                // While the user is actively pressing keys to record a *new* combo, the
                // *currently bound* global hotkey must not also fire (e.g. opening the popup
                // mid-recording just because they pressed its existing shortcut).
                guard let self else { return }
                if isRecording {
                    self.hotKeyManager.unregisterAll()
                } else {
                    self.registerHotKeys()
                }
            }
        )
        popupController.onOpenPreferences = { [weak self] in self?.preferencesController.show() }

        hotKeyManager = HotKeyManager()
        registerHotKeys()

        if !PasteService.hasAccessibilityPermission {
            NSLog("DittoMac: Accessibility permission not yet granted; paste-into-app will prompt on first use.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyManager.unregisterAll()
    }

    private func registerHotKeys() {
        if let toggleCombo = AppSettings.toggleHotKey {
            hotKeyManager.register(id: HotKeyManager.toggleID, combo: toggleCombo) { [weak self] in
                self?.popupController.toggle(centeredOnActiveScreen: true)
            }
        } else {
            // Explicitly cleared — no global shortcut, but the menu bar icon click (wired
            // independently in StatusBarController) still always opens the popup.
            hotKeyManager.unregister(id: HotKeyManager.toggleID)
        }
        for slot in 1...10 {
            let combo = AppSettings.quickPasteHotKey(slot: slot)
            hotKeyManager.register(id: HotKeyManager.quickPasteID(slot: slot), combo: combo) { [weak self] in
                guard let self, let item = self.store.quickPasteItem(at: slot) else { return }
                self.pasteService.rememberFrontmostApp()
                self.pasteService.paste(item)
            }
        }
    }
}
