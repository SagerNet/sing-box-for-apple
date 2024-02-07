import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public extension Color {
    static var textColor: Color {
        #if canImport(UIKit)
            return Color(uiColor: .label)
        #elseif canImport(AppKit)
            return Color(nsColor: .textColor)
        #endif
    }

    static var linkColor: Color {
        #if canImport(UIKit)
            return Color(uiColor: .link)
        #elseif canImport(AppKit)
            return Color(nsColor: .linkColor)
        #endif
    }
}
