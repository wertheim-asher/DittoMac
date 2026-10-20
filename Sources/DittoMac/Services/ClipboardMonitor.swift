import AppKit
import Foundation

/// Polls the system pasteboard for changes and hands captured items to the store.
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private weak var store: ClipboardStore?

    /// Set right before PasteService writes to the pasteboard so we don't re-capture our own paste.
    var suppressNextCapture = false

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if suppressNextCapture {
            suppressNextCapture = false
            return
        }

        guard let item = captureCurrentPasteboard() else { return }
        store?.ingest(item)
    }

    private func frontmostSourceApp() -> (bundleID: String?, name: String?) {
        // The pasteboard doesn't tell us who wrote to it, but in the overwhelming
        // majority of cases the frontmost app is the one that just performed the copy.
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    private func captureCurrentPasteboard() -> ClipItem? {
        let (bundleID, appName) = frontmostSourceApp()
        if let bundleID, store?.isExcluded(bundleID: bundleID) == true {
            return nil
        }

        let now = Date()

        // File URLs (e.g. copied from Finder)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            var item = ClipItem(
                createdAt: now, type: .fileURLs, textContent: nil, rtfData: nil, imageData: nil,
                fileURLsJoined: nil, htmlContent: nil, sourceBundleID: bundleID, sourceAppName: appName,
                isPinned: false, groupID: nil, syncOrigin: nil
            )
            item.fileURLs = urls.map { $0.absoluteString }
            return item
        }

        // Images
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let rep = NSBitmapImageRep(data: imageData),
           let png = rep.representation(using: .png, properties: [:]) {
            return ClipItem(
                createdAt: now, type: .image, textContent: nil, rtfData: nil, imageData: png,
                fileURLsJoined: nil, htmlContent: nil, sourceBundleID: bundleID, sourceAppName: appName,
                isPinned: false, groupID: nil, syncOrigin: nil
            )
        }

        // Rich text (RTF), keep plain-text mirror for search/preview
        if let rtfData = pasteboard.data(forType: .rtf) {
            let plain = pasteboard.string(forType: .string)
            return ClipItem(
                createdAt: now, type: .rtf, textContent: plain, rtfData: rtfData, imageData: nil,
                fileURLsJoined: nil, htmlContent: nil, sourceBundleID: bundleID, sourceAppName: appName,
                isPinned: false, groupID: nil, syncOrigin: nil
            )
        }

        // HTML
        if let htmlData = pasteboard.data(forType: .html), let html = String(data: htmlData, encoding: .utf8) {
            let plain = pasteboard.string(forType: .string)
            return ClipItem(
                createdAt: now, type: .html, textContent: plain, rtfData: nil, imageData: nil,
                fileURLsJoined: nil, htmlContent: html, sourceBundleID: bundleID, sourceAppName: appName,
                isPinned: false, groupID: nil, syncOrigin: nil
            )
        }

        // Plain text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipItem(
                createdAt: now, type: .text, textContent: text, rtfData: nil, imageData: nil,
                fileURLsJoined: nil, htmlContent: nil, sourceBundleID: bundleID, sourceAppName: appName,
                isPinned: false, groupID: nil, syncOrigin: nil
            )
        }

        return nil
    }
}
