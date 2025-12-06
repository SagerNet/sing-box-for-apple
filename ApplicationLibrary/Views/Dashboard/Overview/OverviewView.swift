import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct OverviewView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @StateObject private var coordinator = OverviewViewModel()
    @ObservedObject private var configuration: DashboardCardConfiguration

    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool

    public init(
        _ profileList: Binding<[ProfilePreview]>,
        _ selectedProfileID: Binding<Int64>,
        _ systemProxyAvailable: Binding<Bool>,
        _ systemProxyEnabled: Binding<Bool>,
        cardConfiguration: DashboardCardConfiguration
    ) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
        _systemProxyAvailable = systemProxyAvailable
        _systemProxyEnabled = systemProxyEnabled
        _configuration = ObservedObject(wrappedValue: cardConfiguration)
    }

    public var body: some View {
        Group {
            if configuration.isLoading {
                ProgressView()
            } else {
                ScrollView {
                    cardGrid
                        .padding()
                }
            }
        }
        .alert($coordinator.alert)
        .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || coordinator.reasserting))
    }

    @ViewBuilder
    private var cardGrid: some View {
        let visibleCards = configuration.orderedEnabledCards.filter(shouldShowCard)
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
            return ApplicationLibrary.inPreview || profile.status.isConnected
        case .httpProxy:
            return (ApplicationLibrary.inPreview || profile.status.isConnectedStrict) && systemProxyAvailable
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
        case .uploadTraffic:
            UploadTrafficCard()
                .environmentObject(environments.commandClient)
        case .downloadTraffic:
            DownloadTrafficCard()
                .environmentObject(environments.commandClient)
        case .httpProxy:
            HTTPProxyCard(
                systemProxyAvailable: $systemProxyAvailable,
                systemProxyEnabled: $systemProxyEnabled
            ) { enabled in
                await coordinator.setSystemProxyEnabled(enabled, profile: profile)
            }
        case .clashMode:
            ClashModeCard()
                .environmentObject(environments.commandClient)
        case .profile:
            ProfileCard(
                profileList: $profileList,
                selectedProfileID: Binding(
                    get: { selectedProfileID },
                    set: { newID in
                        coordinator.reasserting = true
                        Task {
                            await coordinator.switchProfile(newID, profile: profile, environments: environments)
                        }
                    }
                )
            )
        }
    }
}
