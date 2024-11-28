import Foundation
import GRDB
import Libbox

public extension Profile {
    nonisolated func updateRemoteProfile() async throws {
        if type != .remote {
            return
        }
        let remoteContent = try HTTPClient().getConfigWithUpdatedURL(remoteURL)
        var error: NSError?
        LibboxCheckConfig(remoteContent.config, &error)
        if let error {
            throw error
        }
        try write(remoteContent.config)
        remoteURL = remoteContent.newURL
        lastUpdated = Date()
        try await ProfileManager.update(self)
    }
}
