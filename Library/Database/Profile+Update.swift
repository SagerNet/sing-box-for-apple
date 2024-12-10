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
        lastUpdated = Date()
        try await ProfileManager.update(self)
        do {
            let oldContent = try read()
            if oldContent == remoteContent {
                return
            }
        } catch {}
        try write(remoteContent)
        try await onProfileUpdated()
    }

    nonisolated func onProfileUpdated() async throws {
        if await SharedPreferences.selectedProfileID.get() == id {
            if let profile = try? await ExtensionProfile.load() {
                if profile.status == .connected {
                    try LibboxNewStandaloneCommandClient()!.serviceReload()
                }
            }
        }
    }
}
