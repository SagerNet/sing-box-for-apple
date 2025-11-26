import Foundation
import Libbox
import SwiftUI

public struct OutboundGroup: Codable, Hashable {
    let tag: String
    let type: String
    var selected: String
    let selectable: Bool
    var isExpand: Bool
    let items: [OutboundGroupItem]

    public func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(selected)
        for item in items {
            hasher.combine(item.urlTestTime)
        }
    }

    public static func == (lhs: OutboundGroup, rhs: OutboundGroup) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

public extension OutboundGroup {
    var displayType: String {
        LibboxProxyDisplayType(type)
    }
}
