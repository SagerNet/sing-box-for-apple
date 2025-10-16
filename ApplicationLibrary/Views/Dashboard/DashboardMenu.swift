import Foundation
import Library
import SwiftUI

@MainActor
public struct DashboardMenu: View {
    @StateObject private var viewModel = DashboardMenuViewModel()

    public init() {}

    public var body: some View {
        Menu {
            ForEach(DashboardCard.allCases) { card in
                Toggle(isOn: Binding(
                    get: { viewModel.enabledCards.contains(card) },
                    set: { _ in
                        Task {
                            await viewModel.toggleCard(card)
                        }
                    }
                )) {
                    Label(card.title, systemImage: card.systemImage)
                }
            }

            Divider()

            Button("Reset to Default") {
                Task {
                    await viewModel.resetToDefault()
                }
            }
        } label: {
            Label("Dashboard Items", systemImage: "square.grid.2x2")
        }
        .onAppear {
            Task {
                await viewModel.loadCards()
            }
        }
    }
}

@MainActor
private final class DashboardMenuViewModel: ObservableObject {
    @Published var enabledCards: [DashboardCard] = []

    func loadCards() async {
        let savedCards = await SharedPreferences.enabledDashboardCards.get()
        if savedCards.isEmpty {
            enabledCards = DashboardCard.defaultCards
        } else {
            enabledCards = savedCards.compactMap { DashboardCard(rawValue: $0) }
        }
    }

    func toggleCard(_ card: DashboardCard) async {
        if enabledCards.contains(card) {
            enabledCards.removeAll { $0 == card }
        } else {
            enabledCards.append(card)
        }
        await SharedPreferences.enabledDashboardCards.set(enabledCards.map(\.rawValue))
    }

    func resetToDefault() async {
        await SharedPreferences.enabledDashboardCards.set([])
        await SharedPreferences.dashboardCardOrder.set([])
        enabledCards = DashboardCard.defaultCards
    }
}
