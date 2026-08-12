import Foundation
import Libbox

public struct OutboundGroup: Codable, Hashable {
    public let tag: String
    public let type: String
    public let displayType: String
    public var selected: String
    public let selectable: Bool
    public var isExpand: Bool
    public var items: [OutboundGroupItem]

    public init(tag: String, type: String, selected: String, selectable: Bool, isExpand: Bool, items: [OutboundGroupItem]) {
        self.tag = tag
        self.type = type
        displayType = LibboxProxyDisplayType(type)
        self.selected = selected
        self.selectable = selectable
        self.isExpand = isExpand
        self.items = items
    }

    public init(_ goGroup: LibboxOutboundGroup) {
        var goItems = [OutboundGroupItem]()
        let itemIterator = goGroup.getItems()!
        while itemIterator.hasNext() {
            goItems.append(OutboundGroupItem(itemIterator.next()!))
        }
        self.init(
            tag: goGroup.tag,
            type: goGroup.type,
            selected: goGroup.selected,
            selectable: goGroup.selectable,
            isExpand: goGroup.isExpand,
            items: goItems
        )
    }
}

public struct OutboundGroupItem: Codable, Hashable {
    public let tag: String
    public let type: String
    public let displayType: String
    public let urlTestTime: Date
    public let urlTestDelay: UInt16

    public init(tag: String, type: String, urlTestTime: Date, urlTestDelay: UInt16) {
        self.tag = tag
        self.type = type
        displayType = LibboxProxyDisplayType(type)
        self.urlTestTime = urlTestTime
        self.urlTestDelay = urlTestDelay
    }

    public init(_ item: LibboxOutboundGroupItem) {
        self.init(
            tag: item.tag,
            type: item.type,
            urlTestTime: Date(timeIntervalSince1970: Double(item.urlTestTime)),
            urlTestDelay: UInt16(item.urlTestDelay)
        )
    }

    public var delayString: String {
        "\(urlTestDelay)ms"
    }
}
