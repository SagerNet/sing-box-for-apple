import Foundation
import Libbox

public struct OutboundGroup: Codable, Hashable {
    public let tag: String
    public let type: String
    public var selected: String
    public let selectable: Bool
    public var isExpand: Bool
    public var items: [OutboundGroupItem]

    public init(tag: String, type: String, selected: String, selectable: Bool, isExpand: Bool, items: [OutboundGroupItem]) {
        self.tag = tag
        self.type = type
        self.selected = selected
        self.selectable = selectable
        self.isExpand = isExpand
        self.items = items
    }

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

    public var displayType: String {
        LibboxProxyDisplayType(type)
    }
}

public struct OutboundGroupItem: Codable, Hashable {
    public let tag: String
    public let type: String
    public let urlTestTime: Date
    public let urlTestDelay: UInt16

    public init(tag: String, type: String, urlTestTime: Date, urlTestDelay: UInt16) {
        self.tag = tag
        self.type = type
        self.urlTestTime = urlTestTime
        self.urlTestDelay = urlTestDelay
    }

    public var displayType: String {
        LibboxProxyDisplayType(type)
    }

    public var delayString: String {
        "\(urlTestDelay)ms"
    }
}
