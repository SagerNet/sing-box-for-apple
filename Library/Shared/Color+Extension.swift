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

#if canImport(UIKit)
    public extension UIColor {
        var relativeLuminance: CGFloat {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            func linearize(_ c: CGFloat) -> CGFloat {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }

            return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
        }

        static func contrastRatio(_ color1: UIColor, _ color2: UIColor) -> CGFloat {
            let l1 = color1.relativeLuminance
            let l2 = color2.relativeLuminance
            let lighter = max(l1, l2)
            let darker = min(l1, l2)
            return (lighter + 0.05) / (darker + 0.05)
        }

        func adjustedForContrast(against background: UIColor, minRatio: CGFloat = 4.5) -> UIColor {
            let currentRatio = Self.contrastRatio(self, background)
            if currentRatio >= minRatio {
                return self
            }

            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let bgLuminance = background.relativeLuminance
            let shouldDarken = bgLuminance > 0.5

            var low: CGFloat = 0
            var high: CGFloat = 1
            var bestColor = self

            for _ in 0 ..< 10 {
                let mid = (low + high) / 2
                let adjusted: UIColor

                if shouldDarken {
                    adjusted = UIColor(
                        red: red * (1 - mid),
                        green: green * (1 - mid),
                        blue: blue * (1 - mid),
                        alpha: alpha
                    )
                } else {
                    adjusted = UIColor(
                        red: red + (1 - red) * mid,
                        green: green + (1 - green) * mid,
                        blue: blue + (1 - blue) * mid,
                        alpha: alpha
                    )
                }

                let ratio = Self.contrastRatio(adjusted, background)
                if ratio >= minRatio {
                    bestColor = adjusted
                    high = mid
                } else {
                    low = mid
                }
            }

            return bestColor
        }
    }

#elseif canImport(AppKit)
    public extension NSColor {
        var relativeLuminance: CGFloat {
            guard let rgbColor = usingColorSpace(.sRGB) else {
                return 0.5
            }

            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            func linearize(_ c: CGFloat) -> CGFloat {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }

            return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
        }

        static func contrastRatio(_ color1: NSColor, _ color2: NSColor) -> CGFloat {
            let l1 = color1.relativeLuminance
            let l2 = color2.relativeLuminance
            let lighter = max(l1, l2)
            let darker = min(l1, l2)
            return (lighter + 0.05) / (darker + 0.05)
        }

        func adjustedForContrast(against background: NSColor, minRatio: CGFloat = 4.5) -> NSColor {
            let currentRatio = Self.contrastRatio(self, background)
            if currentRatio >= minRatio {
                return self
            }

            guard let rgbSelf = usingColorSpace(.sRGB) else {
                return self
            }

            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            rgbSelf.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let bgLuminance = background.relativeLuminance
            let shouldDarken = bgLuminance > 0.5

            var low: CGFloat = 0
            var high: CGFloat = 1
            var bestColor = self

            for _ in 0 ..< 10 {
                let mid = (low + high) / 2
                let adjusted: NSColor

                if shouldDarken {
                    adjusted = NSColor(
                        red: red * (1 - mid),
                        green: green * (1 - mid),
                        blue: blue * (1 - mid),
                        alpha: alpha
                    )
                } else {
                    adjusted = NSColor(
                        red: red + (1 - red) * mid,
                        green: green + (1 - green) * mid,
                        blue: blue + (1 - blue) * mid,
                        alpha: alpha
                    )
                }

                let ratio = Self.contrastRatio(adjusted, background)
                if ratio >= minRatio {
                    bestColor = adjusted
                    high = mid
                } else {
                    low = mid
                }
            }

            return bestColor
        }
    }
#endif
