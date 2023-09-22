import Foundation
import GRDB
import Libbox

public extension Profile {
    nonisolated func updateRemoteProfile() async throws {
        if type != .remote {
            return
        }
        let remoteContent = try HTTPClient().getString(remoteURL)
        var error: NSError?
        LibboxCheckConfig(remoteContent, &error)
        if let error {
            throw error
        }
        try write(remoteContent)
        lastUpdated = Date()
        try await ProfileManager.update(self)
    }
}
