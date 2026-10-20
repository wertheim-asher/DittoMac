import Foundation
import GRDB

enum ClipItemType: String, Codable {
    case text
    case rtf
    case image
    case fileURLs
    case html
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id: Int64?
    var createdAt: Date
    var type: ClipItemType
    var textContent: String?
    var rtfData: Data?
    var imageData: Data?
    var fileURLsJoined: String?
    var htmlContent: String?
    var sourceBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    var groupID: Int64?
    var syncOrigin: String?
    /// 1-based, assigned in copy order, scoped to image-type items only — used to give dragged-out
    /// image files a stable, predictable name ("image_3.png") instead of a generic fixed one.
    var imageSequenceNumber: Int64? = nil

    var fileURLs: [String] {
        get { fileURLsJoined?.split(separator: "\n").map(String.init) ?? [] }
        set { fileURLsJoined = newValue.joined(separator: "\n") }
    }

    var preview: String {
        switch type {
        case .text: return textContent ?? ""
        case .rtf: return textContent ?? "(rich text)"
        case .html: return textContent ?? "(html)"
        case .image: return "(image)"
        case .fileURLs: return fileURLs.map { URL(string: $0)?.lastPathComponent ?? $0 }.joined(separator: ", ")
        }
    }

    /// `id` is only nil for an in-memory item that hasn't been inserted yet; every item that
    /// reaches the UI has already round-tripped through the database and has a real id. This
    /// gives SwiftUI/AppKit call sites a non-optional handle to key selection and scrolling on.
    var stableID: Int64 { id ?? -1 }
}

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clipItem"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let createdAt = Column(CodingKeys.createdAt)
        static let type = Column(CodingKeys.type)
        static let textContent = Column(CodingKeys.textContent)
        static let isPinned = Column(CodingKeys.isPinned)
        static let groupID = Column(CodingKeys.groupID)
        static let sourceBundleID = Column(CodingKeys.sourceBundleID)
    }
}
