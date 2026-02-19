import Library
import SwiftUI

extension ProfileType {
    // UI presentation intentionally keeps iCloud distinct from Local/Remote export semantics.
    var presentationLabel: LocalizedStringKey {
        switch self {
        case .local:
            return "Local"
        case .icloud:
            return "iCloud"
        case .remote:
            return "Remote"
        }
    }

    var presentationSymbol: String {
        switch self {
        case .local:
            return "doc.fill"
        case .icloud:
            return "icloud.fill"
        case .remote:
            return "cloud.fill"
        }
    }
}
