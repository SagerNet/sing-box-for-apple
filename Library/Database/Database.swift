import Foundation
import GRDB

enum Database {
    static let sharedWriter = makeShared()

    private static func makeShared() -> any DatabaseWriter {
        do {
            try FileManager.default.createDirectory(at: FilePath.sharedDirectory, withIntermediateDirectories: true)
            let database = try DatabasePool(path: FilePath.sharedDirectory.appendingPathComponent("settings.db").relativePath)
            var migrator = DatabaseMigrator().disablingDeferredForeignKeyChecks()
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
            migrator.registerMigration("add_auto_update_interval") { db in
                try db.alter(table: "profiles") { t in
                    t.add(column: "autoUpdateInterval", .integer).notNull().defaults(to: 0)
                }
            }
            migrator.registerMigration("fix_cellular_typo") { db in
                try db.execute(sql: "UPDATE preferences SET name = 'exclude_cellular_services' WHERE name = 'exclude_celluar_services'")
            }
            try migrator.migrate(database)
            return database
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
