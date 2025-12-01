import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class OverviewViewModel: BaseViewModel {
    @Published public var reasserting = false

    public func switchProfile(_ profileID: Int64, profile: ExtensionProfile, environments: ExtensionEnvironments) async {
        await SharedPreferences.selectedProfileID.set(profileID)
        environments.selectedProfileUpdate.send()

        if profile.status.isConnected {
            do {
                try await serviceReload()
            } catch {
                alert = Alert(error)
            }
        }
        reasserting = false
    }

    public nonisolated func serviceReload() async throws {
        try LibboxNewStandaloneCommandClient()!.serviceReload()
    }

    public nonisolated func setSystemProxyEnabled(_ enabled: Bool, profile: ExtensionProfile) async {
        do {
            await SharedPreferences.systemProxyEnabled.set(enabled)
            if enabled {
                try LibboxNewStandaloneCommandClient()!.setSystemProxyEnabled(enabled)
            } else {
                await MainActor.run { reasserting = true }
                try await profile.stop()

                var waitSeconds = 0
                while await profile.status != .disconnected {
                    try await Task.sleep(nanoseconds: NSEC_PER_SEC)
                    waitSeconds += 1
                    if waitSeconds >= 5 {
                        throw NSError(domain: "Restart service timeout", code: 0)
                    }
                }
                try await profile.start()
                await MainActor.run { reasserting = false }
            }
        } catch {
            await MainActor.run { alert = Alert(error) }
        }
    }
}
