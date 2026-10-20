import AppKit
import Carbon.HIToolbox

/// Writes clip items back to the system pasteboard and simulates Cmd+V into whatever
/// application was frontmost before our popup stole focus.
final class PasteService {
    private weak var monitor: ClipboardMonitor?
    private weak var store: ClipboardStore?
    private var frontmostBeforePopup: NSRunningApplication?

    init(monitor: ClipboardMonitor, store: ClipboardStore) {
        self.monitor = monitor
        self.store = store
    }

    /// Call this the moment the popup/quick-paste is invoked, before we take focus.
    func rememberFrontmostApp() {
        frontmostBeforePopup = NSWorkspace.shared.frontmostApplication
    }

    static var hasAccessibilityPermission: Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func promptForAccessibilityPermission() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Pastes a single item.
    func paste(_ item: ClipItem) {
        write([item])
        performPaste()
    }

    /// Pastes multiple selected items combined into one block of text, in the given order.
    /// Unlike copyToClipboard, this doesn't save the combination back into history — a paste is
    /// a one-off action into whatever app you're using, not a deliberate "keep this as a clip"
    /// request the way ⌘C is.
    func pasteCombined(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            paste(items[0])
            return
        }
        writeCombinedPlainText(combinedText(for: items))
        performPaste()
    }

    /// ⌘C on a selection: writes to the pasteboard like `pasteCombined`, without simulating
    /// Cmd+V into the frontmost app.
    func copyToClipboard(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            write(items)
        } else {
            let combined = combinedText(for: items)
            writeCombinedPlainText(combined)
            recordCombinedItem(combined)
        }
    }

    /// Joins each item's own text on its own line. Individual captures can carry a trailing
    /// newline from however they were originally copied (e.g. a full line selected in a text
    /// editor) — trimming each one before joining avoids stacking that with our own separator
    /// into a visible blank line between entries. Kept as a plain "\n" join (not the "\r\n" that
    /// actually goes on the pasteboard, see writeCombinedPlainText) so line-counting/search over
    /// the *stored* item stays simple.
    private func combinedText(for items: [ClipItem]) -> String {
        items
            .map { $0.preview.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
    }

    /// Combining several clips produces a genuinely new piece of content the user explicitly
    /// asked to keep — save it back into history as its own reusable clip rather than letting it
    /// only exist transiently on the system pasteboard until overwritten by the next copy.
    private func recordCombinedItem(_ text: String) {
        let item = ClipItem(
            id: nil, createdAt: Date(), type: .text, textContent: text, rtfData: nil, imageData: nil,
            fileURLsJoined: nil, htmlContent: nil, sourceBundleID: nil, sourceAppName: "Combined",
            isPinned: false, groupID: nil, syncOrigin: nil
        )
        store?.ingest(item)
    }

    private func write(_ items: [ClipItem]) {
        guard let item = items.first else { return }
        monitor?.suppressNextCapture = true
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            pb.setString(item.textContent ?? "", forType: .string)
        case .rtf:
            if let rtfData = item.rtfData {
                pb.setData(rtfData, forType: .rtf)
            }
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }
        case .html:
            if let html = item.htmlContent, let data = html.data(using: .utf8) {
                pb.setData(data, forType: .html)
            }
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let data = item.imageData {
                pb.setData(data, forType: .png)
            }
        case .fileURLs:
            let urls = item.fileURLs.compactMap { URL(string: $0) as NSURL? }
            pb.writeObjects(urls)
        }
    }

    /// Actually writes to the pasteboard using "\r\n" — the row-separator convention spreadsheet
    /// apps (Google Sheets, Excel) expect, avoiding a spurious blank row between each line there.
    private func writeCombinedPlainText(_ text: String) {
        monitor?.suppressNextCapture = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text.replacingOccurrences(of: "\n", with: "\r\n"), forType: .string)
    }

    private func performPaste() {
        // Re-activate whatever app was focused before the popup opened, then synthesize Cmd+V.
        frontmostBeforePopup?.activate(options: [])

        guard Self.hasAccessibilityPermission else {
            Self.promptForAccessibilityPermission()
            return
        }

        let delay = DispatchTime.now() + 0.05
        DispatchQueue.main.asyncAfter(deadline: delay) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            let vKeyCode: CGKeyCode = 0x09 // 'v'

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
