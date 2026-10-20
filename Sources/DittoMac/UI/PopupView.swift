import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PopupView: View {
    @ObservedObject var store: ClipboardStore
    let onPasteSingle: (ClipItem) -> Void
    let onPasteMulti: ([ClipItem]) -> Void
    let onCopySelection: ([ClipItem]) -> Void
    let onDismiss: () -> Void
    let onOpenPreferences: () -> Void

    @FocusState private var searchFocused: Bool

    private var selectionBinding: Binding<Set<Int64>> {
        Binding(get: { store.selectedItemIDs }, set: { store.selectedItemIDs = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            groupTabs
            Divider()
            list
            Divider()
            bottomBar
        }
        .frame(width: 420, height: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.separator, lineWidth: 0.5))
        .background(
            // Catches Enter/⌘C/Esc regardless of which control currently has focus. Routing
            // these through SwiftUI keyboard shortcuts (rather than the AppKit local monitor
            // used for arrow keys) matters: they're recognized as key equivalents ahead of the
            // focused search field's own built-in Copy/Cancel handling, so that doesn't also
            // fire alongside ours and beep.
            Group {
                Button("") { pasteSelectionOrFirst() }
                    .keyboardShortcut(.defaultAction)
                Button("") { onCopySelection(store.selectedItemsChronological()) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
        )
        .onChange(of: store.popupOpenCount) { _ in searchFocused = true }
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabButton(title: "All", isSelected: store.selectedGroupID == nil) {
                    store.selectedGroupID = nil
                }
                ForEach(store.groups) { group in
                    tabButton(title: group.name, isSelected: store.selectedGroupID == group.id) {
                        store.selectedGroupID = group.id
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .padding(.bottom, 6)
    }

    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: selectionBinding) {
                ForEach(Array(store.items.enumerated()), id: \.element.stableID) { offset, item in
                    ClipRowView(item: item, index: offset + 1)
                        .contentShape(Rectangle())
                        .onTapGesture { handleClick(on: item) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { onPasteSingle(item) })
                        .contextMenu { contextMenu(for: item) }
                        .onDrag { dragProvider(for: item) }
                        .tag(item.stableID)
                        // Keep selection highlighting a consistent grey instead of switching
                        // between the system accent blue (window key/active) and grey
                        // (inactive) — a plain neutral tint reads the same in both states.
                        .listItemTint(.monochrome)
                }
            }
            .listStyle(.plain)
            .onAppear {
                proxy.scrollTo(store.items.first?.stableID, anchor: .top)
            }
            .onChange(of: store.popupOpenCount) { _ in
                // Deferred a tick so it runs after the row for the new first item exists.
                DispatchQueue.main.async {
                    proxy.scrollTo(store.items.first?.stableID, anchor: .top)
                }
            }
            .onChange(of: store.newCaptureJumpPulse) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(store.items.first?.stableID, anchor: .top)
                }
            }
            .onChange(of: store.keyboardNavPulse) { _ in
                if let id = store.selectionCursorID {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
    }

    private func handleClick(on item: ClipItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            store.toggleSelection(item.stableID)
        } else if flags.contains(.shift) {
            store.selectRange(to: item.stableID)
        } else {
            store.selectOnly(item.stableID)
        }
    }

    /// Right-clicking an item that's part of the current multi-selection applies the action to
    /// the whole selection, matching standard macOS list behavior; right-clicking outside the
    /// current selection acts on just that one item.
    private func contextMenuTargets(for item: ClipItem) -> [ClipItem] {
        if store.selectedItemIDs.contains(item.stableID), store.selectedItemIDs.count > 1 {
            return store.items.filter { store.selectedItemIDs.contains($0.stableID) }
        }
        return [item]
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        let targets = contextMenuTargets(for: item)
        let allPinned = targets.allSatisfy { $0.isPinned }

        Button(allPinned ? "Unpin" : "Pin") { store.setPinned(targets, pinned: !allPinned) }
        Menu("Move to Group") {
            Button("None") { store.move(targets, toGroup: nil) }
            ForEach(store.groups) { group in
                Button(group.name) { store.move(targets, toGroup: group.id) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(targets) }
    }

    /// Lets image/file items be dragged out of the popup and dropped into Finder, Chrome, chat
    /// apps, etc. as the real thing (an actual image file drop, not just clipboard text).
    private func dragProvider(for item: ClipItem) -> NSItemProvider {
        switch item.type {
        case .image:
            // Registers two representations for maximum drop-target compatibility:
            //  - an eagerly-written real file via contentsOf:, which exposes a synchronously
            //    available public.file-url — what a "drag a real file from Finder" style drop
            //    zone typically reads directly.
            //  - registerFileRepresentation's promise-based UTType representation, which is what
            //    got the correct filename through in testing (contentsOf: alone lost it to a
            //    generic name on some drop targets).
            guard let data = item.imageData else { return NSItemProvider() }
            // No extension on suggestedName — the destination appends one derived from the
            // registered UTType itself, so including ".png" here doubled it up ("image 1.png.png").
            let baseName = item.imageSequenceNumber.map { "image \($0)" } ?? "image"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(baseName + ".png")
            guard (try? data.write(to: tempURL)) != nil else { return NSItemProvider() }

            let provider = NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
            provider.suggestedName = baseName
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all
            ) { completion in
                completion(tempURL, true, nil)
                return nil
            }
            return provider
        case .fileURLs:
            guard let first = item.fileURLs.first, let url = URL(string: first) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        case .text, .rtf, .html:
            return NSItemProvider()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit { pasteSelectionOrFirst() }
            Spacer(minLength: 4)
            Text("\(store.items.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func pasteSelectionOrFirst() {
        let selected = store.selectedItemsChronological()
        if selected.count > 1 {
            onPasteMulti(selected)
        } else if let only = selected.first {
            onPasteSingle(only)
        } else if let first = store.items.first {
            onPasteSingle(first)
        }
    }
}
