import Foundation
import SwiftUI

public enum DashboardCard: String, CaseIterable, Identifiable, Codable, Hashable {
    case status
    case connections
    case traffic
    case trafficTotal
    case httpProxy
    case clashMode
    case profile

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .status:
            return "Status"
        case .connections:
            return "Connections"
        case .traffic:
            return "Traffic"
        case .trafficTotal:
            return "Traffic Total"
        case .httpProxy:
            return "HTTP Proxy"
        case .clashMode:
            return "Clash Mode"
        case .profile:
            return "Profile"
        }
    }

    public var systemImage: String {
        switch self {
        case .status:
            return "info.circle.fill"
        case .connections:
            return "link.circle.fill"
        case .traffic:
            return "arrow.up.arrow.down.circle.fill"
        case .trafficTotal:
            return "chart.bar.fill"
        case .httpProxy:
            return "network"
        case .clashMode:
            return "circle.grid.2x2.fill"
        case .profile:
            return "person.crop.circle.fill"
        }
    }

    public var isHalfWidth: Bool {
        switch self {
        case .status, .connections, .traffic, .trafficTotal:
            return true
        case .httpProxy, .clashMode, .profile:
            return false
        }
    }

    public static var defaultCards: [DashboardCard] {
        allCases
    }

    public static var defaultOrder: [DashboardCard] {
        [.status, .connections, .traffic, .trafficTotal, .httpProxy, .clashMode, .profile]
    }
}
