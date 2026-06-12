import Foundation
import GRDB

public extension Notification.Name {
    static let remoteServersUpdated = Notification.Name("remoteServersUpdated")
}

public enum RemoteServerManager {
    public nonisolated static func create(_ server: RemoteServer) async throws {
        server.order = try await nextOrder()
        try await Database.sharedWriter.write { db in
            try server.insert(db, onConflict: .fail)
        }
        postUpdateNotification()
    }

    public nonisolated static func get(_ serverID: Int64) async throws -> RemoteServer? {
        try await Database.sharedWriter.read { db in
            try RemoteServer.fetchOne(db, id: serverID)
        }
    }

    public nonisolated static func delete(_ server: RemoteServer) async throws {
        _ = try await Database.sharedWriter.write { db in
            try server.delete(db)
        }
        postUpdateNotification()
    }

    public nonisolated static func delete(by id: [Int64]) async throws -> Int {
        let count = try await Database.sharedWriter.write { db in
            try RemoteServer.deleteAll(db, ids: id)
        }
        postUpdateNotification()
        return count
    }

    public nonisolated static func update(_ server: RemoteServer) async throws {
        _ = try await Database.sharedWriter.write { db in
            try server.updateChanges(db)
        }
        postUpdateNotification()
    }

    public nonisolated static func update(_ serverList: [RemoteServer]) async throws {
        try await Database.sharedWriter.write { db in
            for server in serverList {
                try server.updateChanges(db)
            }
        }
        postUpdateNotification()
    }

    public nonisolated static func list() async throws -> [RemoteServer] {
        try await Database.sharedWriter.read { db in
            try RemoteServer.all().order(Column("order").asc).fetchAll(db)
        }
    }

    private nonisolated static func nextOrder() async throws -> UInt32 {
        try await Database.sharedWriter.read { db in
            try UInt32(RemoteServer.fetchCount(db))
        }
    }

    private nonisolated static func postUpdateNotification() {
        NotificationCenter.default.post(name: .remoteServersUpdated, object: nil)
    }
}
