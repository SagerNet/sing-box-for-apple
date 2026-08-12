import Library
import SwiftUI

public extension Color {
    static func urlTestDelay(_ delay: UInt16) -> Color {
        switch delay {
        case 0:
            return .urlTestNeutral
        case ..<800:
            return .urlTestGood
        case 800 ..< 1500:
            return .urlTestMedium
        default:
            return .urlTestBad
        }
    }

    static let urlTestGood = dynamic(light: Color(red: 0.239, green: 0.506, blue: 0.408), dark: Color(red: 0.486, green: 0.722, blue: 0.620))
    static let urlTestMedium = dynamic(light: Color(red: 0.659, green: 0.455, blue: 0.184), dark: Color(red: 0.827, green: 0.643, blue: 0.369))
    static let urlTestBad = dynamic(light: Color(red: 0.761, green: 0.369, blue: 0.196), dark: Color(red: 0.859, green: 0.541, blue: 0.384))
    static let urlTestNeutral = dynamic(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.09))

    private static func dynamic(light: Color, dark: Color) -> Color {
        #if os(macOS)
            return Color(NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                    NSColor(dark)
                } else {
                    NSColor(light)
                }
            })
        #else
            return Color(UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    UIColor(dark)
                } else {
                    UIColor(light)
                }
            })
        #endif
    }
}

public extension OutboundGroupItem {
    var delayColor: Color {
        Color.urlTestDelay(urlTestDelay)
    }
}
