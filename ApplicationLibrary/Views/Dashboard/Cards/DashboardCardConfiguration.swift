import Foundation
import Library

@MainActor
public final class DashboardCardConfiguration: ObservableObject {
    @Published public private(set) var enabledCards: [DashboardCard] = []
    @Published public private(set) var cardOrder: [DashboardCard] = []
    @Published public private(set) var isLoading = true

    public init() {
        Task {
            await reload()
        }
    }

    public func reload() async {
        isLoading = true
        enabledCards = await loadEnabledCards()
        cardOrder = await loadCardOrder()
        isLoading = false
    }

    public func isEnabled(_ card: DashboardCard) -> Bool {
        enabledCards.contains(card)
    }

    public func toggleCard(_ card: DashboardCard) {
        guard card != .profile else { return }

        // Update state synchronously so UI reflects change immediately
        if enabledCards.contains(card) {
            enabledCards.removeAll { $0 == card }
        } else {
            enabledCards = insertInOrder(card, into: enabledCards)
        }

        // Save asynchronously in background
        Task {
            await saveEnabledCards()
        }
    }

    public func moveCard(from source: IndexSet, to destination: Int) async {
        cardOrder.move(fromOffsets: source, toOffset: destination)
        await saveCardOrder()
    }

    public func resetToDefault() async {
        await SharedPreferences.enabledDashboardCards.set([])
        await SharedPreferences.dashboardCardOrder.set([])
        await reload()
    }

    public var orderedEnabledCards: [DashboardCard] {
        cardOrder.filter { enabledCards.contains($0) }
    }

    private func loadEnabledCards() async -> [DashboardCard] {
        let saved = await SharedPreferences.enabledDashboardCards.get()
        guard !saved.isEmpty else { return DashboardCard.defaultCards }

        var cards = saved.compactMap { DashboardCard(rawValue: $0) }
        if !cards.contains(.profile) {
            cards.append(.profile)
            await SharedPreferences.enabledDashboardCards.set(cards.map(\.rawValue))
        }
        return cards
    }

    private func loadCardOrder() async -> [DashboardCard] {
        let saved = await SharedPreferences.dashboardCardOrder.get()
        guard !saved.isEmpty else { return DashboardCard.defaultOrder }

        var order = saved.compactMap { DashboardCard(rawValue: $0) }
        let existingSet = Set(order)
        let newCards = DashboardCard.allCases.filter { !existingSet.contains($0) }
        order.append(contentsOf: newCards)
        return order
    }

    private func saveEnabledCards() async {
        await SharedPreferences.enabledDashboardCards.set(enabledCards.map(\.rawValue))
    }

    private func saveCardOrder() async {
        await SharedPreferences.dashboardCardOrder.set(cardOrder.map(\.rawValue))
    }

    private func insertInOrder(_ card: DashboardCard, into cards: [DashboardCard]) -> [DashboardCard] {
        guard let cardIndex = cardOrder.firstIndex(of: card) else {
            return cards + [card]
        }

        let insertIndex = cards.filter { enabledCard in
            guard let enabledIndex = cardOrder.firstIndex(of: enabledCard) else { return false }
            return enabledIndex < cardIndex
        }.count

        var result = cards
        result.insert(card, at: insertIndex)
        return result
    }
}
