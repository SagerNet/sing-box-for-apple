import Foundation

public class ExtensionEnvironments: ObservableObject {
    @Published public var logClient = CommandClient(.log)
    @Published public var extensionProfileLoading = true
    @Published public var extensionProfile: ExtensionProfile?

    public init() {}

    deinit {
        logClient.disconnect()
    }

    public func postReload() {
        Task {
            await reload()
        }
    }

    public nonisolated func reload() async {
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil || extensionProfile?.status == .invalid {
                newProfile.register()
                await MainActor.run {
                    extensionProfile = newProfile
                    extensionProfileLoading = false
                }
            }
        } else {
            await MainActor.run {
                extensionProfile = nil
                extensionProfileLoading = false
            }
        }
    }

    public func connectLog() {
        guard let profile = extensionProfile else {
            return
        }
        if profile.status.isConnected, !logClient.isConnected {
            logClient.connect()
        }
    }
}
