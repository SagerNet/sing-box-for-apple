import BinaryCodable
import Foundation
import GRDB

extension SharedPreferences {
    public class Preference<T: Codable> {
        private let name: String
        private let defaultValue: T

        init(_ name: String, defaultValue: T) {
            self.name = name
            self.defaultValue = defaultValue
        }

        public nonisolated func get() async -> T {
            do {
                return try await SharedPreferences.read(name) ?? defaultValue
            } catch {
                NSLog("read preferences error: \(error)")
                return defaultValue
            }
        }

        public func getBlocking() -> T {
            runBlocking { [self] in
                await get()
            }
        }

        public nonisolated func set(_ newValue: T?) async {
            do {
                try await SharedPreferences.write(name, newValue)
            } catch {
                NSLog("write preferences error: \(error)")
            }
        }
    }

    private nonisolated static func read<T: Codable>(_ name: String) async throws -> T? {
        guard let item = try await (Database.sharedWriter.read { db in
            try Item.fetchOne(db, id: name)
        })
        else {
            return nil
        }
        return try BinaryDecoder().decode(from: item.data)
    }

    private nonisolated static func write(_ name: String, _ value: (some Codable)?) async throws {
        if value == nil {
            _ = try await Database.sharedWriter.write { db in
                try Item.deleteOne(db, id: name)
            }
        } else {
            let data = try BinaryEncoder().encode(value)
            try await Database.sharedWriter.write { db in
                try Item(name: name, data: data).insert(db)
            }
        }
    }
}

private class Item: Record, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
        super.init()
    }

    override public class var databaseTableName: String {
        "preferences"
    }

    enum Columns: String, ColumnExpression {
        case name, data
    }

    required init(row: Row) throws {
        name = row[Columns.name]
        data = row[Columns.data]
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.name] = name
        container[Columns.data] = data
    }
}
