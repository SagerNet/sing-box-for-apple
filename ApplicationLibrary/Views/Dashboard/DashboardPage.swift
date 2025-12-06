import Foundation
import Library
import SwiftUI

public enum DashboardPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case overview
    case groups
    case connections
}

public extension DashboardPage {
    static func enabledCases() -> [DashboardPage] {
        [.overview, .groups, .connections]
    }

    static func enabledCases(hasGroups: Bool) -> [DashboardPage] {
        var cases: [DashboardPage] = [.overview]
        if hasGroups {
            cases.append(.groups)
        }
        cases.append(.connections)
        return cases
    }
}

public extension DashboardPage {
    var title: String {
        switch self {
        case .overview:
            return String(localized: "Overview")
        case .groups:
            return String(localized: "Groups")
        case .connections:
            return String(localized: "Connections")
        }
    }

    var label: some View {
        switch self {
        case .overview:
            return Label(title, systemImage: "text.and.command.macwindow")
        case .groups:
            return Label(title, systemImage: "rectangle.3.group.fill")
        case .connections:
            return Label(title, systemImage: "list.bullet.rectangle.portrait.fill")
        }
    }

    @MainActor
    func contentView(_ profileList: Binding<[ProfilePreview]>, _ selectedProfileID: Binding<Int64>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>, _ cardConfiguration: DashboardCardConfiguration) -> some View {
        Group {
            switch self {
            case .overview:
                OverviewView(profileList, selectedProfileID, systemProxyAvailable, systemProxyEnabled, cardConfiguration: cardConfiguration)
            case .groups:
                GroupListView()
            case .connections:
                ConnectionListView()
            }
        }
    }
}
