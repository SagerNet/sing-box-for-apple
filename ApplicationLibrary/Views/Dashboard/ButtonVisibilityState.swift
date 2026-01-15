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

        let actualGroupsCount = commandClient.groups?.count ?? 0
        let screenshotFallbackGroupsCount = 2
        groupsCount = Variant.screenshotMode && actualGroupsCount == 0
            ? screenshotFallbackGroupsCount
            : actualGroupsCount
        connectionsCount = Int(commandClient.status?.connectionsIn ?? 0)

        let isConnected = Variant.screenshotMode || profile.status.isConnectedStrict

        let hasGroups = Variant.screenshotMode || (commandClient.groups?.isEmpty == false)

        showConnectionsButton = isConnected
        showGroupsButton = isConnected && hasGroups
    }

    private mutating func reset() {
        showGroupsButton = false
        showConnectionsButton = false
        groupsCount = 0
        connectionsCount = 0
    }
}
