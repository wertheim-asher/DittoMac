import AppKit
import Combine
import Foundation
import GRDB

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var groups: [ClipGroup] = []
    @Published private(set) var excludedApps: [ExcludedApp] = []
    @Published var searchText: String = "" { didSet { refresh() } }
    @Published var selectedGroupID: Int64? = nil { didSet { refresh() } }

    /// Bumped every time the popup is about to be shown. The popup view is created once and
    /// reused, so this is the reliable signal for "reset selection to the first item" — unlike
    /// observing `items`, it still fires even when the list content hasn't changed since last time.
    @Published private(set) var popupOpenCount: Int = 0
    func notifyPopupWillShow() {
        popupOpenCount += 1
        selectFirstItem()
    }

    /// Same idea for the Preferences window — reset which tab is showing without paying the
    /// cost of rebuilding its whole SwiftUI/AppKit hierarchy on every open.
    @Published private(set) var preferencesOpenCount: Int = 0
    func notifyPreferencesWillShow() { preferencesOpenCount += 1 }

    /// Bumped whenever a new (or refreshed-to-top) capture lands, so the popup — if it's
    /// currently open, e.g. you take a screenshot while it's on screen — follows it to the top
    /// instead of leaving you scrolled wherever you were with the new item out of view.
    @Published private(set) var newCaptureJumpPulse: Int = 0
    private func jumpToNewestCapture() {
        selectFirstItem()
        newCaptureJumpPulse += 1
    }

    // MARK: - Selection
    //
    // Lives here (rather than as local SwiftUI @State in PopupView) because both the SwiftUI
    // view (mouse clicks) and PopupPanelController (arrow keys, ⌘C — plain AppKit event
    // handling, no view identity to hang @State off of) need to read and drive it.

    @Published var selectedItemIDs: Set<Int64> = []
    /// Fixed end of a range — where a shift-click/shift-arrow selection started.
    @Published private(set) var selectionAnchorID: Int64?
    /// The active/moving end — what arrow keys move and what the popup scrolls to keep visible.
    @Published private(set) var selectionCursorID: Int64?

    /// Bumped whenever the keyboard (not a click) moved the selection, so the popup can scroll
    /// the newly-selected row into view without forcing it to the top the way opening does.
    @Published private(set) var keyboardNavPulse: Int = 0

    func selectFirstItem() {
        let id = items.first?.stableID
        selectedItemIDs = id.map { [$0] } ?? []
        selectionAnchorID = id
        selectionCursorID = id
    }

    func selectOnly(_ id: Int64) {
        selectedItemIDs = [id]
        selectionAnchorID = id
        selectionCursorID = id
    }

    func toggleSelection(_ id: Int64) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
        selectionCursorID = id
    }

    func selectRange(to id: Int64) {
        guard let anchor = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { $0.stableID == anchor }),
              let targetIndex = items.firstIndex(where: { $0.stableID == id }) else {
            selectOnly(id)
            return
        }
        let range = anchorIndex < targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        selectedItemIDs = Set(items[range].map { $0.stableID })
        selectionCursorID = id
    }

    /// Plain arrow key: move a single-item selection, collapsing any multi-selection —
    /// standard arrow-key list navigation behavior.
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.stableID == selectionCursorID }) ?? 0
        let newIndex = min(max(currentIndex + delta, 0), items.count - 1)
        selectOnly(items[newIndex].stableID)
        keyboardNavPulse += 1
    }

    /// Shift+arrow key: extends/shrinks the range from the fixed anchor toward the new cursor
    /// position, the way Finder/Mail list selection works.
    func extendSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        if selectionAnchorID == nil { selectionAnchorID = selectionCursorID ?? items.first?.stableID }

        let currentIndex = items.firstIndex(where: { $0.stableID == selectionCursorID }) ?? 0
        let newIndex = min(max(currentIndex + delta, 0), items.count - 1)
        selectionCursorID = items[newIndex].stableID

        guard let anchor = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { $0.stableID == anchor }) else { return }
        let range = anchorIndex < newIndex ? anchorIndex...newIndex : newIndex...anchorIndex
        selectedItemIDs = Set(items[range].map { $0.stableID })
        keyboardNavPulse += 1
    }

    func selectedItemsChronological() -> [ClipItem] {
        items
            .filter { selectedItemIDs.contains($0.stableID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Called with every newly-captured *local* item so SyncService can broadcast it. Not called for
    /// items that arrived from a peer (see receiveRemoteItem) to avoid echo loops.
    var onNewLocalItem: ((ClipItem) -> Void)?

    private let db = AppDatabase.shared.dbQueue
    private let defaults = UserDefaults.standard

    var maxItems: Int {
        get { defaults.object(forKey: "maxItems") as? Int ?? 500 }
        set { defaults.set(newValue, forKey: "maxItems") }
    }

    var maxAgeDays: Int {
        get { defaults.object(forKey: "maxAgeDays") as? Int ?? 0 } // 0 = unlimited
        set { defaults.set(newValue, forKey: "maxAgeDays") }
    }

    init() {
        refresh()
        refreshGroups()
        refreshExcludedApps()
    }

    // MARK: - Ingestion

    func ingest(_ newItem: ClipItem) {
        // Skip consecutive exact duplicates (same as Ditto's default behavior) — a genuine no-op,
        // not worth even bumping the timestamp on.
        if let mostRecent = try? db.read({ db in
            try ClipItem.order(ClipItem.Columns.createdAt.desc).fetchOne(db)
        }), isDuplicate(newItem, of: mostRecent) {
            return
        }

        insertOrRefreshDuplicate(newItem)
        purgeIfNeeded()
        refresh()
        jumpToNewestCapture()

        if newItem.syncOrigin == nil {
            onNewLocalItem?(newItem)
        }
    }

    /// Entry point for items arriving from a paired peer over LAN sync.
    func receiveRemoteItem(_ item: ClipItem) {
        insertOrRefreshDuplicate(item)
        purgeIfNeeded()
        refresh()
        jumpToNewestCapture()
    }

    /// If this content already exists anywhere in history (any position, not just the most
    /// recent item), that occurrence is refreshed/consolidated instead of leaving a stale
    /// duplicate buried further down:
    ///  - If a *pinned* copy already exists, the recopy is a no-op — a pin means "keep this
    ///    permanently," so it's never touched by dedup, and there's no reason to also create a
    ///    fresh unpinned entry for content the user already has kept.
    ///  - Otherwise the single most relevant unpinned duplicate is bumped to "now" (preserving
    ///    its id/group), and any other stray unpinned duplicates — e.g. left over from before
    ///    this existed — are cleaned up at the same time.
    private func insertOrRefreshDuplicate(_ newItem: ClipItem) {
        try? db.write { db in
            let all = try ClipItem.fetchAll(db)
            let duplicates = all.filter { self.isDuplicate(newItem, of: $0) }

            if duplicates.contains(where: { $0.isPinned }) {
                for stray in duplicates where !stray.isPinned {
                    if let id = stray.id { _ = try ClipItem.deleteOne(db, key: id) }
                }
                return
            }

            if var primary = duplicates.first {
                for stray in duplicates.dropFirst() {
                    if let id = stray.id { _ = try ClipItem.deleteOne(db, key: id) }
                }
                primary.createdAt = newItem.createdAt
                primary.sourceBundleID = newItem.sourceBundleID
                primary.sourceAppName = newItem.sourceAppName
                primary.syncOrigin = newItem.syncOrigin
                try primary.update(db)
            } else {
                var item = newItem
                item.id = nil
                if item.type == .image {
                    item.imageSequenceNumber = self.nextImageSequenceNumber()
                }
                try item.insert(db)
            }
        }
    }

    /// 1-based, incremented once per newly-captured (not re-refreshed) image — see
    /// `ClipItem.imageSequenceNumber`.
    private func nextImageSequenceNumber() -> Int64 {
        let next = Int64(defaults.integer(forKey: "nextImageSequenceNumber")) + 1
        defaults.set(next, forKey: "nextImageSequenceNumber")
        return next
    }

    private func isDuplicate(_ a: ClipItem, of b: ClipItem) -> Bool {
        // Text/RTF/HTML are compared purely by their plain-text mirror, trimmed — the same
        // words re-copied from a different app (and so captured in a different format, or with
        // incidental trailing whitespace) should still count as the same content.
        let textTypes: Set<ClipItemType> = [.text, .rtf, .html]
        if textTypes.contains(a.type), textTypes.contains(b.type) {
            let normA = a.textContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normB = b.textContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            return normA == normB && !(normA ?? "").isEmpty
        }
        guard a.type == b.type else { return false }
        switch a.type {
        case .image: return a.imageData == b.imageData
        case .fileURLs: return a.fileURLsJoined == b.fileURLsJoined
        default: return false
        }
    }

    // MARK: - Reading / filtering

    func refresh() {
        items = (try? db.read { db -> [ClipItem] in
            var request = ClipItem.order(ClipItem.Columns.isPinned.desc, ClipItem.Columns.createdAt.desc)
            if let groupID = selectedGroupID {
                request = request.filter(ClipItem.Columns.groupID == groupID)
            }
            if !searchText.isEmpty {
                let pattern = "%\(searchText)%"
                request = request.filter(ClipItem.Columns.textContent.like(pattern))
            }
            return try request.limit(1000).fetchAll(db)
        }) ?? []

        // If whatever was selected fell out of the new result set (e.g. a search filtered it
        // out), fall back to the first item rather than leaving a dangling/empty selection.
        let validIDs = Set(items.map { $0.stableID })
        if selectedItemIDs.isEmpty || selectedItemIDs.isDisjoint(with: validIDs) {
            selectFirstItem()
        }
    }

    /// Item N (1-indexed, 0 = 10th) from the unfiltered, ungrouped top-of-history list, for quick-paste hotkeys.
    func quickPasteItem(at position: Int) -> ClipItem? {
        try? db.read { db in
            try ClipItem
                .order(ClipItem.Columns.isPinned.desc, ClipItem.Columns.createdAt.desc)
                .limit(1, offset: position - 1)
                .fetchOne(db)
        } ?? nil
    }

    // MARK: - Mutations

    func togglePin(_ item: ClipItem) {
        guard item.id != nil else { return }
        var updated = item
        updated.isPinned.toggle()
        try? db.write { db in
            try updated.update(db)
        }
        refresh()
    }

    /// Pins/unpins every given item to the same target state, e.g. from a multi-select context
    /// menu — unlike `togglePin`, everything ends up in the *same* state regardless of where
    /// each one started (no risk of scrambling a mixed pinned/unpinned selection).
    func setPinned(_ items: [ClipItem], pinned: Bool) {
        try? db.write { db in
            for item in items where item.isPinned != pinned {
                var updated = item
                updated.isPinned = pinned
                try updated.update(db)
            }
        }
        refresh()
    }

    func delete(_ item: ClipItem) {
        delete([item])
    }

    func delete(_ items: [ClipItem]) {
        try? db.write { db in
            for item in items {
                if let id = item.id {
                    _ = try ClipItem.deleteOne(db, key: id)
                }
            }
        }
        refresh()
    }

    func move(_ item: ClipItem, toGroup groupID: Int64?) {
        move([item], toGroup: groupID)
    }

    func move(_ items: [ClipItem], toGroup groupID: Int64?) {
        try? db.write { db in
            for item in items {
                var updated = item
                updated.groupID = groupID
                try updated.update(db)
            }
        }
        refresh()
    }

    func clearAll(keepPinned: Bool = true) {
        _ = try? db.write { db in
            if keepPinned {
                try ClipItem.filter(ClipItem.Columns.isPinned == false).deleteAll(db)
            } else {
                try ClipItem.deleteAll(db)
            }
        }
        resetImageSequenceCounterToHighestRemaining()
        refresh()
    }

    /// The counter itself lives in UserDefaults (see nextImageSequenceNumber), separate from the
    /// clipItem rows — clearing history wouldn't otherwise touch it, leaving new images numbered
    /// as if nothing had been deleted. Reset to the highest number still present (0 if none) so
    /// numbering picks up correctly whether or not any pinned images survived the clear.
    private func resetImageSequenceCounterToHighestRemaining() {
        let highest = (try? db.read { db in
            try ClipItem.fetchAll(db).compactMap { $0.imageSequenceNumber }.max()
        }) ?? nil
        defaults.set(Int(highest ?? 0), forKey: "nextImageSequenceNumber")
    }

    private func purgeIfNeeded() {
        try? db.write { db in
            let count = try ClipItem.filter(ClipItem.Columns.isPinned == false).fetchCount(db)
            if count > self.maxItems {
                let excess = count - self.maxItems
                let stale = try ClipItem
                    .filter(ClipItem.Columns.isPinned == false)
                    .order(ClipItem.Columns.createdAt.asc)
                    .limit(excess)
                    .fetchAll(db)
                for s in stale {
                    if let id = s.id {
                        _ = try ClipItem.deleteOne(db, key: id)
                    }
                }
            }

            if self.maxAgeDays > 0 {
                let cutoff = Date().addingTimeInterval(-Double(self.maxAgeDays) * 86400)
                try ClipItem
                    .filter(ClipItem.Columns.isPinned == false)
                    .filter(ClipItem.Columns.createdAt < cutoff)
                    .deleteAll(db)
            }
        }
    }

    // MARK: - Groups

    func refreshGroups() {
        groups = (try? db.read { db in
            try ClipGroup.order(ClipGroup.Columns.sortOrder.asc).fetchAll(db)
        }) ?? []
    }

    func addGroup(named name: String) {
        var group = ClipGroup(name: name, sortOrder: groups.count)
        try? db.write { db in try group.insert(db) }
        refreshGroups()
    }

    func deleteGroup(_ group: ClipGroup) {
        guard let id = group.id else { return }
        try? db.write { db in
            _ = try ClipGroup.deleteOne(db, key: id)
        }
        if selectedGroupID == id { selectedGroupID = nil }
        refreshGroups()
        refresh()
    }

    func renameGroup(_ group: ClipGroup, to name: String) {
        var updated = group
        updated.name = name
        try? db.write { db in try updated.update(db) }
        refreshGroups()
    }

    // MARK: - Excluded apps

    func refreshExcludedApps() {
        excludedApps = (try? db.read { db in
            try ExcludedApp.order(ExcludedApp.Columns.appName.asc).fetchAll(db)
        }) ?? []
    }

    func isExcluded(bundleID: String) -> Bool {
        excludedApps.contains { $0.bundleID == bundleID }
    }

    func addExcludedApp(bundleID: String, appName: String) {
        guard !isExcluded(bundleID: bundleID) else { return }
        var app = ExcludedApp(bundleID: bundleID, appName: appName)
        try? db.write { db in try app.insert(db) }
        refreshExcludedApps()
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        guard let id = app.id else { return }
        try? db.write { db in
            _ = try ExcludedApp.deleteOne(db, key: id)
        }
        refreshExcludedApps()
    }
}
