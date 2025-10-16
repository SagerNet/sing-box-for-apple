import Foundation
import Library

extension OverviewViewModel {
    func loadEnabledCards() async -> [DashboardCard] {
        let savedCards = await SharedPreferences.enabledDashboardCards.get()
        if savedCards.isEmpty {
            return DashboardCard.defaultCards
        }
        return savedCards.compactMap { DashboardCard(rawValue: $0) }
    }

    func loadCardOrder() async -> [DashboardCard] {
        let savedOrder = await SharedPreferences.dashboardCardOrder.get()
        if savedOrder.isEmpty {
            return DashboardCard.defaultOrder
        }
        return savedOrder.compactMap { DashboardCard(rawValue: $0) }
    }

    func saveEnabledCards(_ cards: [DashboardCard]) async {
        await SharedPreferences.enabledDashboardCards.set(cards.map(\.rawValue))
    }

    func saveCardOrder(_ cards: [DashboardCard]) async {
        await SharedPreferences.dashboardCardOrder.set(cards.map(\.rawValue))
    }

    func isCardEnabled(_ card: DashboardCard, in enabledCards: [DashboardCard]) -> Bool {
        enabledCards.contains(card)
    }

    func toggleCard(_ card: DashboardCard, enabledCards: [DashboardCard]) async -> [DashboardCard] {
        var newEnabledCards = enabledCards
        if newEnabledCards.contains(card) {
            newEnabledCards.removeAll { $0 == card }
        } else {
            newEnabledCards.append(card)
        }
        await saveEnabledCards(newEnabledCards)
        return newEnabledCards
    }

    func resetCardsToDefault() async {
        await SharedPreferences.enabledDashboardCards.set([])
        await SharedPreferences.dashboardCardOrder.set([])
    }

    func getOrderedEnabledCards(enabledCards: [DashboardCard], order: [DashboardCard]) -> [DashboardCard] {
        order.filter { enabledCards.contains($0) }
    }
}
