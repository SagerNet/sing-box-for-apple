import Foundation
import SwiftUI

public enum ANSIColors {
    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[;\\d]*m")
    private static let cache: NSCache<NSString, CachedAttributedString> = {
        let cache = NSCache<NSString, CachedAttributedString>()
        cache.countLimit = 3000
        return cache
    }()

    private static let logRed = Color(red: 1.0, green: 0.13, blue: 0.35)
    private static let logGreen = Color(red: 0.18, green: 0.8, blue: 0.44)
    private static let logYellow = Color(red: 0.9, green: 0.9, blue: 0.0)
    private static let logBlue = Color(red: 0.2, green: 0.6, blue: 0.86)
    private static let logPurple = Color(red: 0.61, green: 0.35, blue: 0.71)
    private static let logBlueLight = Color(red: 0.36, green: 0.68, blue: 0.89)
    private static let logWhite = Color(red: 0.93, green: 0.94, blue: 0.95)

    public static func clearCache() {
        cache.removeAllObjects()
    }

    public static func parseAnsiString(_ text: String) -> AttributedString {
        let nsString = text as NSString
        if let cached = cache.object(forKey: nsString) {
            return cached.value
        }
        let matches = ansiRegex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        if matches.isEmpty {
            let plain = AttributedString(text)
            cache.setObject(CachedAttributedString(plain), forKey: nsString)
            return plain
        }

        var cleanText = text
        for match in matches.reversed() {
            cleanText = (cleanText as NSString).replacingCharacters(in: match.range, with: "") as String
        }

        var attributedString = AttributedString(cleanText)
        var currentStyle: AttributeContainer?
        var currentStart = 0
        var offset = 0

        for match in matches {
            let code = nsString.substring(with: match.range)
            let codeStart = match.range.location - offset

            if let style = parseAnsiCode(code) {
                if let existingStyle = currentStyle, currentStart < codeStart {
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: currentStart)
                    let endIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: codeStart)
                    attributedString[startIndex ..< endIndex].mergeAttributes(existingStyle)
                }
                currentStyle = style
                currentStart = codeStart
            } else {
                if let existingStyle = currentStyle, currentStart < codeStart {
                    let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: currentStart)
                    let endIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: codeStart)
                    attributedString[startIndex ..< endIndex].mergeAttributes(existingStyle)
                }
                currentStyle = nil
                currentStart = codeStart
            }

            offset += match.range.length
        }

        if let existingStyle = currentStyle, currentStart < cleanText.count {
            let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: currentStart)
            attributedString[startIndex...].mergeAttributes(existingStyle)
        }

        cache.setObject(CachedAttributedString(attributedString), forKey: nsString)
        return attributedString
    }

    private static func parseAnsiCode(_ code: String) -> AttributeContainer? {
        let codeString = code.dropFirst(2).dropLast()
        let colorCodes = codeString.split(separator: ";").map { String($0) }

        var container = AttributeContainer()
        var hasAttribute = false

        for codeStr in colorCodes {
            switch codeStr {
            case "0":
                return nil
            case "1":
                container.font = .system(.caption2, design: .monospaced).bold()
                hasAttribute = true
            case "3":
                container.font = .system(.caption2, design: .monospaced).italic()
                hasAttribute = true
            case "4":
                container.underlineStyle = .single
                hasAttribute = true
            case "30":
                container.foregroundColor = .black
                hasAttribute = true
            case "31":
                container.foregroundColor = logRed
                hasAttribute = true
            case "32":
                container.foregroundColor = logGreen
                hasAttribute = true
            case "33":
                container.foregroundColor = logYellow
                hasAttribute = true
            case "34":
                container.foregroundColor = logBlue
                hasAttribute = true
            case "35":
                container.foregroundColor = logPurple
                hasAttribute = true
            case "36":
                container.foregroundColor = logBlueLight
                hasAttribute = true
            case "37":
                container.foregroundColor = logWhite
                hasAttribute = true
            default:
                if let codeInt = Int(codeStr), codeInt >= 38, codeInt <= 125 {
                    let adjustedCode = codeInt % 125
                    let row = adjustedCode / 36
                    let column = adjustedCode % 36
                    container.foregroundColor = Color(
                        red: Double(row * 51) / 255.0,
                        green: Double((column / 6) * 51) / 255.0,
                        blue: Double((column % 6) * 51) / 255.0
                    )
                    hasAttribute = true
                }
            }
        }

        return hasAttribute ? container : nil
    }
}

private final class CachedAttributedString: NSObject {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}
