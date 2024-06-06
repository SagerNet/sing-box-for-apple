import Foundation
import SwiftUI

public enum ConnectionListPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case active
    case closed
}

public extension ConnectionListPage {
    var title: String {
        switch self {
        case .active:
            return NSLocalizedString("Active", comment: "")
        case .closed:
            return NSLocalizedString("Closed", comment: "")
        }
    }

    var label: some View {
        switch self {
        case .active:
            return Label(title, systemImage: "play.fill")
        case .closed:
            return Label(title, systemImage: "stop.fill")
        }
    }
}
