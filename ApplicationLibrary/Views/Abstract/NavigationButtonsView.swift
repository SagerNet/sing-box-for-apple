import SwiftUI

@MainActor
public struct NavigationButtonsView: View {
    public let showGroupsButton: Bool
    public let showConnectionsButton: Bool
    public let groupsCount: Int
    public let connectionsCount: Int
    public let onGroupsTap: () -> Void
    public let onConnectionsTap: () -> Void

    public init(
        showGroupsButton: Bool,
        showConnectionsButton: Bool,
        groupsCount: Int,
        connectionsCount: Int,
        onGroupsTap: @escaping () -> Void,
        onConnectionsTap: @escaping () -> Void
    ) {
        self.showGroupsButton = showGroupsButton
        self.showConnectionsButton = showConnectionsButton
        self.groupsCount = groupsCount
        self.connectionsCount = connectionsCount
        self.onGroupsTap = onGroupsTap
        self.onConnectionsTap = onConnectionsTap
    }

    public var body: some View {
        HStack(spacing: 12) {
            if showConnectionsButton {
                Divider()
                Text(verbatim: "\(connectionsCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button {
                    onConnectionsTap()
                } label: {
                    Label("Connections", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
            }
            if showGroupsButton {
                Divider()
                Text(verbatim: "\(groupsCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button {
                    onGroupsTap()
                } label: {
                    Label("Groups", systemImage: "rectangle.3.group.fill")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
            }
        }
    }
}
