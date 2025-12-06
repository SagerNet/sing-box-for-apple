import Foundation
import Library

@MainActor
public struct ButtonVisibilityState {
    public var showGroupsButton = false
    public var showConnectionsButton = false
    public var groupsCount = 0
    public var connectionsCount = 0

    public init() {}

    public mutating func update(
        profile: ExtensionProfile?,
        commandClient: CommandClient
    ) {
        guard let profile else {
            reset()
            return
        }

        groupsCount = commandClient.groups?.count ?? 0
        connectionsCount = commandClient.connections?.count ?? 0

        let isConnected = ApplicationLibrary.inPreview || profile.status.isConnectedStrict

        showConnectionsButton = isConnected
        showGroupsButton = isConnected && (commandClient.groups?.isEmpty == false)
    }

    private mutating func reset() {
        showGroupsButton = false
        showConnectionsButton = false
        groupsCount = 0
        connectionsCount = 0
    }
}
