import Library
import SwiftUI

@MainActor
public struct RemoteDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @ObservedObject private var commandClient: CommandClient
    @ObservedObject private var cardConfiguration: DashboardCardConfiguration

    #if os(tvOS)
        @State private var showCardManagement = false
        @State private var showRemoteControl = false
        @State private var showGroups = false
        @State private var showConnections = false
        @State private var buttonState = ButtonVisibilityState()
    #endif

    public init(commandClient: CommandClient, cardConfiguration: DashboardCardConfiguration) {
        _commandClient = ObservedObject(wrappedValue: commandClient)
        _cardConfiguration = ObservedObject(wrappedValue: cardConfiguration)
    }

    public var body: some View {
        Group {
            if commandClient.isConnected {
                ScrollView {
                    cardGrid
                        .padding()
                        .environmentObject(commandClient)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            environments.connect()
        }
        .onChangeCompat(of: scenePhase) { phase in
            guard phase == .active else {
                return
            }
            environments.connect()
        }
        #if os(tvOS)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                NavigationButtonsView(
                    showGroupsButton: buttonState.showGroupsButton,
                    showConnectionsButton: buttonState.showConnectionsButton,
                    groupsCount: buttonState.groupsCount,
                    connectionsCount: buttonState.connectionsCount,
                    onGroupsTap: { showGroups = true },
                    onConnectionsTap: { showConnections = true }
                )
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showCardManagement = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                Button {
                    showRemoteControl = true
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                Button {
                    environments.exitRemoteControl()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                }
            }
        }
        .navigationDestination(isPresented: $showGroups) {
            GroupListView()
                .navigationTitle("Groups")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        .navigationDestination(isPresented: $showConnections) {
            ConnectionListView()
                .navigationTitle("Connections")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        .navigationDestination(isPresented: $showCardManagement) {
            CardManagementView(onDisappear: {
                Task { await cardConfiguration.reload() }
            })
            .navigationTitle("Dashboard Items")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    BackButton()
                }
            }
        }
        .navigationDestination(isPresented: $showRemoteControl) {
            RemoteControlView()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        .onReceive(commandClient.$groups) { _ in
            updateButtonVisibility()
        }
        .onReceive(commandClient.$isConnected) { _ in
            updateButtonVisibility()
        }
        .onAppear {
            updateButtonVisibility()
        }
        #endif
    }

    #if os(tvOS)
        private func updateButtonVisibility() {
            buttonState.update(remoteClient: commandClient)
        }
    #endif

    @ViewBuilder
    private var cardGrid: some View {
        let visibleCards = cardConfiguration.orderedEnabledCards.filter(shouldShowCard)
        let groupedCards = groupCards(visibleCards)

        VStack(spacing: 16) {
            ForEach(Array(groupedCards.enumerated()), id: \.offset) { _, group in
                if group.count == 2 {
                    HStack(spacing: 16) {
                        cardView(for: group[0])
                            .frame(maxWidth: .infinity)
                        cardView(for: group[1])
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    cardView(for: group[0])
                }
            }
        }
    }

    private func groupCards(_ cards: [DashboardCard]) -> [[DashboardCard]] {
        var result: [[DashboardCard]] = []
        var index = 0

        while index < cards.count {
            let card = cards[index]
            if card.isHalfWidth, index + 1 < cards.count, cards[index + 1].isHalfWidth {
                result.append([card, cards[index + 1]])
                index += 2
            } else {
                result.append([card])
                index += 1
            }
        }
        return result
    }

    private func shouldShowCard(_ card: DashboardCard) -> Bool {
        switch card {
        case .status, .connections, .uploadTraffic, .downloadTraffic, .clashMode:
            return true
        case .httpProxy, .profile:
            return false
        }
    }

    @ViewBuilder
    private func cardView(for card: DashboardCard) -> some View {
        switch card {
        case .status:
            StatusCard()
        case .connections:
            ConnectionsCard()
        case .uploadTraffic:
            UploadTrafficCard()
        case .downloadTraffic:
            DownloadTrafficCard()
        case .clashMode:
            ClashModeCard()
        case .httpProxy, .profile:
            EmptyView()
        }
    }
}
