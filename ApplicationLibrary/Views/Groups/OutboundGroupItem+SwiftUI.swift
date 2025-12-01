import Library
import SwiftUI

public extension OutboundGroupItem {
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
