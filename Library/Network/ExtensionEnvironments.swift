import Foundation
import SwiftUI

@MainActor
public class ExtensionEnvironments: ObservableObject {
    @Published public var commandClient = CommandClient([.log, .status, .groups, .clashMode, .connections])
    @Published public var extensionProfileLoading = true
    @Published public var extensionProfile: ExtensionProfile?
    @Published public var emptyProfiles = false

    public let profileUpdate = ObjectWillChangePublisher()
    public let selectedProfileUpdate = ObjectWillChangePublisher()
    public let openSettings = ObjectWillChangePublisher()

    public init() {}

    nonisolated deinit {
        Task { @MainActor in
            commandClient.disconnect()
        }
    }

    public func postReload() {
        Task {
            await reload()
        }
    }

    public func reload() async {
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil || extensionProfile?.status == .invalid {
                newProfile.register()
                extensionProfile = newProfile
                extensionProfileLoading = false
            }
        } else {
            extensionProfile = nil
            extensionProfileLoading = false
        }
    }

    public func connect() {
        guard let profile = extensionProfile else {
            return
        }
        if profile.status.isConnected, !commandClient.isConnected {
            commandClient.connect()
        }
    }
}
