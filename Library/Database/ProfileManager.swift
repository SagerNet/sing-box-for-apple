import Foundation
import GRDB

public enum ProfileManager {
    public nonisolated static func create(_ profile: Profile) async throws {
        profile.order = try await nextOrder()
        try await Database.sharedWriter().write { db in
            try profile.insert(db, onConflict: .fail)
        }
    }

    public nonisolated static func get(_ profileID: Int64) async throws -> Profile? {
        try await Database.sharedWriter().read { db in
            try Profile.fetchOne(db, id: profileID)
        }
    }

    public nonisolated static func get(by profileName: String) async throws -> Profile? {
        try await Database.sharedWriter().read { db in
            try Profile.filter(Column("name") == profileName).fetchOne(db)
        }
    }

    public nonisolated static func delete(_ profile: Profile) async throws {
        _ = try await Database.sharedWriter().write { db in
            try profile.delete(db)
        }
    }

    public nonisolated static func delete(by id: Int64) async throws {
        _ = try await Database.sharedWriter().write { db in
            try Profile.deleteOne(db, id: id)
        }
    }

    public nonisolated static func delete(_ profileList: [Profile]) async throws -> Int {
        try await Database.sharedWriter().write { db in
            try Profile.deleteAll(db, keys: profileList.map {
                ["id": $0.id!]
            })
        }
    }

    public nonisolated static func delete(by id: [Int64]) async throws -> Int {
        try await Database.sharedWriter().write { db in
            try Profile.deleteAll(db, ids: id)
        }
    }

    public nonisolated static func update(_ profile: Profile) async throws {
        _ = try await Database.sharedWriter().write { db in
            try profile.updateChanges(db)
        }
    }

    public nonisolated static func update(_ profileList: [Profile]) async throws {
        // TODO: batch update
        try await Database.sharedWriter().write { db in
            for profile in profileList {
                try profile.updateChanges(db)
            }
        }
    }

    public nonisolated static func list() async throws -> [Profile] {
        try await Database.sharedWriter().read { db in
            try Profile.all().order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func listRemote() async throws -> [Profile] {
        try await Database.sharedWriter().read { db in
            try Profile.filter(Column("type") == ProfileType.remote.rawValue).order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func listAutoUpdateEnabled() async throws -> [Profile] {
        try await Database.sharedWriter().read { db in
            try Profile.filter(Column("autoUpdate") == true).order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func nextID() async throws -> Int64 {
        try await Database.sharedWriter().read { db in
            if let lastProfile = try Profile.select(Column("id")).order(Column("id").desc).fetchOne(db) {
                return lastProfile.id! + 1
            } else {
                return 1
            }
        }
    }

    private nonisolated static func nextOrder() async throws -> UInt32 {
        try await Database.sharedWriter().read { db in
            try UInt32(Profile.fetchCount(db))
        }
    }
}
