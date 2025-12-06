import Foundation
import SwiftUI

public enum DashboardCard: String, CaseIterable, Identifiable, Codable, Hashable {
    case status
    case connections
    case uploadTraffic
    case downloadTraffic
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
        case .uploadTraffic:
            return "Upload"
        case .downloadTraffic:
            return "Download"
        case .httpProxy:
            return "System HTTP Proxy"
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
        case .uploadTraffic:
            return "arrow.up.circle.fill"
        case .downloadTraffic:
            return "arrow.down.circle.fill"
        case .httpProxy:
            return "network"
        case .clashMode:
            return "circle.grid.2x2.fill"
        case .profile:
            return "doc.text.fill"
        }
    }

    public var isHalfWidth: Bool {
        switch self {
        case .status, .connections, .uploadTraffic, .downloadTraffic:
            return true
        case .httpProxy, .clashMode, .profile:
            return false
        }
    }

    public static var defaultCards: [DashboardCard] {
        allCases
    }

    public static var defaultOrder: [DashboardCard] {
        [.uploadTraffic, .downloadTraffic, .status, .connections, .httpProxy, .clashMode, .profile]
    }
}
