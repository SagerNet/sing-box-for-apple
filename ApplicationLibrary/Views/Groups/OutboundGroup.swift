import Foundation
import SwiftUI

public struct OutboundGroup: Codable {
    let tag: String
    let type: String
    var selected: String
    let selectable: Bool
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
        switch type {
        case "selector":
            return "Selector"
        case "urltest":
            return "URLTest"
        default:
            return "Unknown"
        }
    }
}
