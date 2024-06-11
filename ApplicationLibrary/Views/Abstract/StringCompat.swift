import Foundation
import SwiftUI

public extension Bool {
    func toString() -> String {
        if self {
            return String(localized: "true")
        } else {
            return String(localized: "false")
        }
    }
}
