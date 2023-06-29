import Foundation
import GRDB

class Database {
    private static var writer: (any DatabaseWriter)?

    static func sharedWriter() throws -> any DatabaseWriter {
        if let writer {
            return writer
        }
        let database = try DatabasePool(path: FilePath.sharedDirectory.appendingPathComponent("settings.db").relativePath)
        var migrator = DatabaseMigrator().disablingDeferredForeignKeyChecks()
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("initialize") { db in
            try db.create(table: "profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("order", .integer).notNull()
                t.column("type", .integer).notNull().defaults(to: ProfileType.local.rawValue)
                t.column("path", .text).notNull()
                t.column("remoteURL", .text)
                t.column("autoUpdate", .boolean).notNull().defaults(to: false)
                t.column("lastUpdated", .datetime)
            }
            try db.create(table: "preferences") { t in
                t.primaryKey("name", .text, onConflict: .replace).notNull()
                t.column("data", .blob)
            }
        }

        try migrator.migrate(database)
        writer = database
        return database
    }
}
