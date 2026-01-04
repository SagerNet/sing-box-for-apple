import Foundation
import os

public extension Logger {
    init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier!, category: category)
    }
}
