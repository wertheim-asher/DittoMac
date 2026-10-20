import SwiftUI
import AppKit

struct ClipRowView: View {
    let item: ClipItem
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            icon
            VStack(alignment: .leading, spacing: 2) {
                content
                if !isCombined, let appName = item.sourceAppName {
                    Text(appName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isCombined {
                Text("Combined")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }
            if hasMoreLines {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .help("This item has more lines than shown")
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// A combined item's "source" isn't a single app, so it's marked this way instead (see
    /// PasteService.recordCombinedItem) — shown as a distinct tag rather than in the normal
    /// source-app label slot, so it reads as metadata about the row rather than as if it were
    /// part of the copied text itself.
    private var isCombined: Bool { item.sourceAppName == "Combined" }

    /// Non-empty lines of the preview, in order. Some source apps copy multi-line text with a
    /// blank line between each line (paragraph-style copy behavior) — filtering those out means
    /// the 2-line truncated preview always shows two lines of actual content instead of "line 1"
    /// followed by nothing.
    private var meaningfulLines: [String] {
        item.preview
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whether there's more content than the 2-line row can show — a visual cue (Ditto shows the
    /// same kind of truncation) that pasting this item will produce more than what's visible here.
    private var hasMoreLines: Bool {
        guard item.type != .image else { return false }
        return meaningfulLines.count > 2
    }

    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .text, .rtf, .html: Image(systemName: "doc.text").foregroundStyle(.secondary)
        case .image: Image(systemName: "photo").foregroundStyle(.secondary)
        case .fileURLs: Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
            } else {
                Text("Image")
            }
        default:
            Text(meaningfulLines.joined(separator: "\n"))
                .lineLimit(2)
                .font(.system(size: 12))
        }
    }
}
