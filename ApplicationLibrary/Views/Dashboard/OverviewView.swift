import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct OverviewView: View {
    @Environment(\.selection) private var selection
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool
    @StateObject private var viewModel = OverviewViewModel()

    @State private var enabledCards: [DashboardCard] = []
    @State private var cardOrder: [DashboardCard] = []

    private var selectedProfileIDLocal: Binding<Int64> {
        $selectedProfileID.withSetter { newValue in
            viewModel.reasserting = true
            Task { [self] in
                await viewModel.switchProfile(newValue, profile: profile, environments: environments)
            }
        }
    }

    public init(_ profileList: Binding<[ProfilePreview]>, _ selectedProfileID: Binding<Int64>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
        _systemProxyAvailable = systemProxyAvailable
        _systemProxyEnabled = systemProxyEnabled
    }

    public var body: some View {
        Group {
            if profileList.isEmpty {
                VStack {
                    Spacer()
                    Text("Empty profiles")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    cardGrid
                        .padding()
                }
            }
        }
        .onAppear {
            Task {
                enabledCards = await viewModel.loadEnabledCards()
                cardOrder = await viewModel.loadCardOrder()
            }
        }
        .alertBinding($viewModel.alert)
        .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || viewModel.reasserting))
    }

    @ViewBuilder
    private var cardGrid: some View {
        let orderedCards = viewModel.getOrderedEnabledCards(enabledCards: enabledCards, order: cardOrder)
        let visibleCards = orderedCards.filter { shouldShowCard($0) }
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
        case .status, .connections, .traffic, .trafficTotal:
            return ApplicationLibrary.inPreview || profile.status.isConnected
        case .httpProxy:
            return (ApplicationLibrary.inPreview || profile.status.isConnectedStrict) && systemProxyAvailable
        case .clashMode:
            return ApplicationLibrary.inPreview || profile.status.isConnected
        case .profile:
            return true
        }
    }

    @ViewBuilder
    private func cardView(for card: DashboardCard) -> some View {
        switch card {
        case .status:
            StatusCard()
                .environmentObject(environments.commandClient)
        case .connections:
            ConnectionsCard()
                .environmentObject(environments.commandClient)
        case .traffic:
            TrafficCard()
                .environmentObject(environments.commandClient)
        case .trafficTotal:
            TrafficTotalCard()
                .environmentObject(environments.commandClient)
        case .httpProxy:
            HTTPProxyCard(
                systemProxyAvailable: $systemProxyAvailable,
                systemProxyEnabled: $systemProxyEnabled
            ) { newValue in
                await viewModel.setSystemProxyEnabled(newValue, profile: profile)
            }
        case .clashMode:
            ClashModeCard()
                .environmentObject(environments.commandClient)
        case .profile:
            ProfileCard(
                profileList: $profileList,
                selectedProfileID: selectedProfileIDLocal
            )
        }
    }
}
