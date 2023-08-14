import Foundation
import Libbox
import SwiftUI

public struct OutboundGroup: Codable {
    let tag: String
    let type: String
    var selected: String
    let selectable: Bool
    var isExpand: Bool
    let items: [OutboundGroupItem]

    var hashValue: Int {
        var value = tag.hashValue
        (value, _) = value.addingReportingOverflow(selected.hashValue)
        for item in items {
            (value, _) = value.addingReportingOverflow(item.urlTestTime.hashValue)
        }
        return value
    }
}

public extension OutboundGroup {
    var displayType: String {
        LibboxProxyDisplayType(type)
    }
}
