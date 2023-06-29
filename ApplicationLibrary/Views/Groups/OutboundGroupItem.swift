import Foundation
import SwiftUI

public struct OutboundGroupItem: Codable {
    public let tag: String
    public let type: String

    public let urlTestTime: Date
    public let urlTestDelay: UInt16
}

public extension OutboundGroupItem {
    var delayString: String {
        "\(urlTestDelay)ms"
    }

    var delayColor: Color {
        switch urlTestDelay {
        case 0:
            return .gray
        case ..<800:
            return .green
        case 800 ..< 1500:
            return .yellow
        default:
            return .orange
        }
    }
}
