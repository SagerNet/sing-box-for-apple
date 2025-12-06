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
        #if os(tvOS)
            tvOSBody
        #else
            iOSBody
        #endif
    }

    #if os(tvOS)
        private var tvOSBody: some View {
            HStack {
                if showConnectionsButton {
                    Button {
                        onConnectionsTap()
                    } label: {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                    }
                }
                if showGroupsButton {
                    Button {
                        onGroupsTap()
                    } label: {
                        Image(systemName: "rectangle.3.group.fill")
                    }
                }
            }
        }
    #else
        private var iOSBody: some View {
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
    #endif
}
