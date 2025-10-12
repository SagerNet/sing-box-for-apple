import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class OverviewViewModel: ObservableObject {
    @Published var alert: Alert?
    @Published var reasserting = false

    public init() {}

    func switchProfile(_ newProfileID: Int64, profile: ExtensionProfile, environments: ExtensionEnvironments) async {
        await SharedPreferences.selectedProfileID.set(newProfileID)
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

    nonisolated func serviceReload() async throws {
        try LibboxNewStandaloneCommandClient()!.serviceReload()
    }

    nonisolated func setSystemProxyEnabled(_ isEnabled: Bool, profile: ExtensionProfile) async {
        do {
            await SharedPreferences.systemProxyEnabled.set(isEnabled)
            if isEnabled {
                try LibboxNewStandaloneCommandClient()!.setSystemProxyEnabled(isEnabled)
            } else {
                // Apple BUG: HTTP Proxy cannot be disabled via setTunnelNetworkSettings, so we can only restart the Network Extension
                await MainActor.run {
                    reasserting = true
                }
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
                await MainActor.run {
                    reasserting = false
                }
            }
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
