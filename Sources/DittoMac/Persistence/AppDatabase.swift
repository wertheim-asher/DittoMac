import Foundation
import GRDB

final class AppDatabase {
    static let shared = try! AppDatabase(path: AppDatabase.defaultPath())

    let dbQueue: DatabaseQueue

    private static func defaultPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("DittoMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ditto.sqlite").path
    }

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "clipGroup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "clipItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull()
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("rtfData", .blob)
                t.column("imageData", .blob)
                t.column("fileURLsJoined", .text)
                t.column("htmlContent", .text)
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("groupID", .integer).indexed().references("clipGroup", onDelete: .setNull)
                t.column("syncOrigin", .text)
            }
            try db.create(index: "idx_clipItem_createdAt", on: "clipItem", columns: ["createdAt"])

            try db.create(table: "excludedApp") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundleID", .text).notNull().unique()
                t.column("appName", .text).notNull()
            }

            try db.create(table: "syncPeer") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("peerID", .text).notNull().unique()
                t.column("displayName", .text).notNull()
                t.column("trusted", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "clipItem") { t in
                t.add(column: "imageSequenceNumber", .integer)
            }
        }

        return migrator
    }
}
