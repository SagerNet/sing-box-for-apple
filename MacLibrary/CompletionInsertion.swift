import Foundation

enum CompletionRetrigger {
    case none
    case keys
    case values
}

struct CompletionInsertionPlan {
    let text: String
    let cursorOffset: Int
    let retrigger: CompletionRetrigger
}

struct ResolvedInsertion {
    let range: NSRange
    let text: String
    let cursorLocation: Int
}

enum CompletionInsertion {
    static func keyInsertion(name: String, shape: SchemaValueShape?, colonFollows: Bool, siblingFollows: Bool, indent: String) -> CompletionInsertionPlan {
        if colonFollows {
            let text = "\"\(name)\""
            return CompletionInsertionPlan(text: text, cursorOffset: (text as NSString).length, retrigger: .none)
        }
        let prefix = "\"\(name)\": "
        let prefixLength = (prefix as NSString).length
        switch shape ?? .ambiguous {
        case .array:
            let container = expandedContainer(open: "[", close: "]", indent: indent)
            return plan(text: prefix + container.text, cursorOffset: prefixLength + container.cursorOffset, appendComma: siblingFollows, retrigger: .values)
        case .object:
            let container = expandedContainer(open: "{", close: "}", indent: indent)
            return plan(text: prefix + container.text, cursorOffset: prefixLength + container.cursorOffset, appendComma: siblingFollows, retrigger: .keys)
        case .string:
            return plan(text: prefix + "\"\"", cursorOffset: prefixLength + 1, appendComma: siblingFollows, retrigger: .values)
        case .scalar, .ambiguous:
            return plan(text: prefix, cursorOffset: prefixLength, appendComma: false, retrigger: .values)
        }
    }

    static func formInsertion(shape: SchemaValueShape, siblingFollows: Bool, indent: String) -> CompletionInsertionPlan? {
        switch shape {
        case .array:
            let container = expandedContainer(open: "[", close: "]", indent: indent)
            return plan(text: container.text, cursorOffset: container.cursorOffset, appendComma: siblingFollows, retrigger: .values)
        case .object:
            let container = expandedContainer(open: "{", close: "}", indent: indent)
            return plan(text: container.text, cursorOffset: container.cursorOffset, appendComma: siblingFollows, retrigger: .keys)
        case .string:
            return plan(text: "\"\"", cursorOffset: 1, appendComma: siblingFollows, retrigger: .none)
        default:
            return nil
        }
    }

    private static func plan(text: String, cursorOffset: Int, appendComma: Bool, retrigger: CompletionRetrigger) -> CompletionInsertionPlan {
        CompletionInsertionPlan(text: appendComma ? text + "," : text, cursorOffset: cursorOffset, retrigger: retrigger)
    }

    private static func expandedContainer(open: String, close: String, indent: String) -> (text: String, cursorOffset: Int) {
        let innerIndent = indent + "  "
        let text = open + "\n" + innerIndent + "\n" + indent + close
        return (text, 2 + (innerIndent as NSString).length)
    }

    static func lineIndent(in string: NSString, at location: Int) -> String {
        var lineStart = min(max(location, 0), string.length)
        while lineStart > 0 {
            let character = string.character(at: lineStart - 1)
            if character == 0x0A || character == 0x0D {
                break
            }
            lineStart -= 1
        }
        var index = lineStart
        while index < string.length, index < location {
            let character = string.character(at: index)
            if character == 0x20 || character == 0x09 {
                index += 1
            } else {
                break
            }
        }
        return string.substring(with: NSRange(location: lineStart, length: index - lineStart))
    }

    static func arrayExampleInsertion(elements: [String], siblingFollows: Bool, indent: String) -> CompletionInsertionPlan {
        let innerIndent = indent + "  "
        let body = elements.map { innerIndent + "\"\($0)\"" }.joined(separator: ",\n")
        let text = "[\n" + body + "\n" + indent + "]"
        return plan(text: text, cursorOffset: (text as NSString).length, appendComma: siblingFollows, retrigger: .none)
    }

    static func valueInsertion(text valueText: String, quoted: Bool, siblingFollows: Bool) -> CompletionInsertionPlan {
        var text = quoted ? "\"\(valueText)\"" : valueText
        let cursorOffset = (text as NSString).length
        if siblingFollows {
            text += ","
        }
        return CompletionInsertionPlan(text: text, cursorOffset: cursorOffset, retrigger: .none)
    }

    static func resolve(plan: CompletionInsertionPlan, replacing range: NSRange, in string: NSString, expandingFrom openOffset: Int? = nil) -> ResolvedInsertion {
        if let openOffset, let expanded = expandedResolution(plan: plan, replacing: range, in: string, openOffset: openOffset) {
            return expanded
        }
        var resolvedRange = range
        var prefix = ""
        if let commaPoint = leadingCommaInsertionPoint(in: string, before: range.location) {
            prefix = "," + string.substring(with: NSRange(location: commaPoint, length: range.location - commaPoint))
            resolvedRange = NSRange(location: commaPoint, length: range.location - commaPoint + range.length)
        }
        return ResolvedInsertion(
            range: resolvedRange,
            text: prefix + plan.text,
            cursorLocation: resolvedRange.location + (prefix as NSString).length + plan.cursorOffset
        )
    }

    private static func expandedResolution(plan: CompletionInsertionPlan, replacing range: NSRange, in string: NSString, openOffset: Int) -> ResolvedInsertion? {
        guard openOffset >= 0, openOffset < range.location, range.location + range.length <= string.length else {
            return nil
        }
        let opener = string.character(at: openOffset)
        guard opener != unichar(UInt8(ascii: "\"")), let closer = pairCloser(forOpener: opener) else {
            return nil
        }
        var index = openOffset + 1
        while index < range.location {
            let character = string.character(at: index)
            guard character == 0x20 || character == 0x09 else {
                return nil
            }
            index += 1
        }
        index = range.location + range.length
        while index < string.length {
            let character = string.character(at: index)
            if character == 0x20 || character == 0x09 {
                index += 1
                continue
            }
            break
        }
        guard index < string.length, string.character(at: index) == closer else {
            return nil
        }
        let indent = lineIndent(in: string, at: openOffset)
        let innerIndent = indent + "  "
        let shifted = shiftLines(of: plan, by: "  ")
        let prefix = "\n" + innerIndent
        return ResolvedInsertion(
            range: NSRange(location: openOffset + 1, length: index - (openOffset + 1)),
            text: prefix + shifted.text + "\n" + indent,
            cursorLocation: openOffset + 1 + (prefix as NSString).length + shifted.cursorOffset
        )
    }

    private static func shiftLines(of plan: CompletionInsertionPlan, by extra: String) -> (text: String, cursorOffset: Int) {
        let source = plan.text as NSString
        let extraLength = (extra as NSString).length
        var text = ""
        var cursorOffset = plan.cursorOffset
        var index = 0
        while index < source.length {
            let character = source.character(at: index)
            text += String(utf16CodeUnits: [character], count: 1)
            if character == 0x0A {
                text += extra
                if index < plan.cursorOffset {
                    cursorOffset += extraLength
                }
            }
            index += 1
        }
        return (text, cursorOffset)
    }

    static func isTypedNewlineInsertion(_ text: String) -> Bool {
        var newlineFound = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n", "\r":
                newlineFound = true
            case " ", "\t":
                continue
            default:
                return false
            }
        }
        return newlineFound
    }

    static func isWhitespaceOnlyLine(in string: NSString, at location: Int) -> Bool {
        let length = string.length
        guard location >= 0, location <= length else {
            return false
        }
        var index = location
        while index > 0 {
            let character = string.character(at: index - 1)
            if character == 0x0A || character == 0x0D {
                break
            }
            guard character == 0x20 || character == 0x09 else {
                return false
            }
            index -= 1
        }
        index = location
        while index < length {
            let character = string.character(at: index)
            if character == 0x0A || character == 0x0D {
                break
            }
            guard character == 0x20 || character == 0x09 else {
                return false
            }
            index += 1
        }
        return true
    }

    static func typedAutoCommaPoint(typedCharacter: unichar, context: JSONCursorContext?, in string: NSString, before position: Int) -> Int? {
        guard let context, case .siblingSlot = context.kind, let container = context.containers.last else {
            return nil
        }
        if container.isObject {
            guard typedCharacter == unichar(UInt8(ascii: "\"")) else {
                return nil
            }
        } else {
            guard isValueStartCharacter(typedCharacter) else {
                return nil
            }
        }
        return leadingCommaInsertionPoint(in: string, before: position)
    }

    static func pairCloser(forOpener character: unichar) -> unichar? {
        switch character {
        case unichar(UInt8(ascii: "{")):
            return unichar(UInt8(ascii: "}"))
        case unichar(UInt8(ascii: "[")):
            return unichar(UInt8(ascii: "]"))
        case unichar(UInt8(ascii: "\"")):
            return unichar(UInt8(ascii: "\""))
        default:
            return nil
        }
    }

    static func isValueStartCharacter(_ character: unichar) -> Bool {
        switch character {
        case unichar(UInt8(ascii: "\"")), unichar(UInt8(ascii: "{")), unichar(UInt8(ascii: "[")),
             unichar(UInt8(ascii: "0")) ... unichar(UInt8(ascii: "9")),
             unichar(UInt8(ascii: "-")),
             unichar(UInt8(ascii: "t")), unichar(UInt8(ascii: "f")), unichar(UInt8(ascii: "n")):
            return true
        default:
            return false
        }
    }

    static func leadingCommaInsertionPoint(in string: NSString, before start: Int) -> Int? {
        var index = min(start, string.length) - 1
        while index >= 0 {
            let character = string.character(at: index)
            switch character {
            case 0x20, 0x09, 0x0A, 0x0D:
                index -= 1
            case unichar(UInt8(ascii: "/")):
                guard index >= 1, string.character(at: index - 1) == unichar(UInt8(ascii: "*")),
                      let open = blockCommentOpen(in: string, closingAt: index)
                else {
                    return nil
                }
                index = open - 1
            default:
                if let commentStart = lineCommentStart(in: string, covering: index) {
                    index = commentStart - 1
                    continue
                }
                switch character {
                case unichar(UInt8(ascii: "\"")), unichar(UInt8(ascii: "}")), unichar(UInt8(ascii: "]")),
                     unichar(UInt8(ascii: "0")) ... unichar(UInt8(ascii: "9")),
                     unichar(UInt8(ascii: "e")), unichar(UInt8(ascii: "l")):
                    return index + 1
                default:
                    return nil
                }
            }
        }
        return nil
    }

    private static func commentEnd(in string: NSString, at index: Int) -> Int? {
        guard index + 1 < string.length, string.character(at: index) == unichar(UInt8(ascii: "/")) else {
            return nil
        }
        let next = string.character(at: index + 1)
        if next == unichar(UInt8(ascii: "/")) {
            var end = index + 2
            while end < string.length {
                let character = string.character(at: end)
                if character == 0x0A || character == 0x0D {
                    break
                }
                end += 1
            }
            return end
        }
        if next == unichar(UInt8(ascii: "*")) {
            var end = index + 2
            while end + 1 < string.length {
                if string.character(at: end) == unichar(UInt8(ascii: "*")), string.character(at: end + 1) == unichar(UInt8(ascii: "/")) {
                    return end + 2
                }
                end += 1
            }
            return string.length
        }
        return nil
    }

    private static func blockCommentOpen(in string: NSString, closingAt closer: Int) -> Int? {
        var index = closer - 2
        while index >= 0 {
            if string.character(at: index) == unichar(UInt8(ascii: "/")), string.character(at: index + 1) == unichar(UInt8(ascii: "*")) {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func lineCommentStart(in string: NSString, covering position: Int) -> Int? {
        var lineStart = position
        while lineStart > 0 {
            let character = string.character(at: lineStart - 1)
            if character == 0x0A || character == 0x0D {
                break
            }
            lineStart -= 1
        }
        var index = lineStart
        var inString = false
        while index < position {
            let character = string.character(at: index)
            if inString {
                if character == unichar(UInt8(ascii: "\\")) {
                    index += 2
                    continue
                }
                if character == unichar(UInt8(ascii: "\"")) {
                    inString = false
                }
                index += 1
                continue
            }
            if character == unichar(UInt8(ascii: "\"")) {
                inString = true
                index += 1
                continue
            }
            guard let end = commentEnd(in: string, at: index) else {
                index += 1
                continue
            }
            if end > position {
                return index
            }
            index = end
        }
        return nil
    }

    static func siblingFollows(in string: NSString, from start: Int, containerIsObject: Bool) -> Bool {
        var index = start
        while index < string.length {
            let character = string.character(at: index)
            switch character {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            case unichar(UInt8(ascii: "/")):
                guard let end = commentEnd(in: string, at: index) else {
                    return false
                }
                index = end
            case unichar(UInt8(ascii: "\"")):
                return true
            default:
                if containerIsObject {
                    return false
                }
                switch character {
                case unichar(UInt8(ascii: "{")), unichar(UInt8(ascii: "[")),
                     unichar(UInt8(ascii: "0")) ... unichar(UInt8(ascii: "9")),
                     unichar(UInt8(ascii: "-")),
                     unichar(UInt8(ascii: "a")) ... unichar(UInt8(ascii: "z")),
                     unichar(UInt8(ascii: "A")) ... unichar(UInt8(ascii: "Z")):
                    return true
                default:
                    return false
                }
            }
        }
        return false
    }

    private static func scaffold(name: String, value: String, cursorInsideValue: Bool, appendComma: Bool, retrigger: CompletionRetrigger) -> CompletionInsertionPlan {
        var text = "\"\(name)\": " + value
        let cursorOffset = (text as NSString).length - (cursorInsideValue ? 1 : 0)
        if appendComma {
            text += ","
        }
        return CompletionInsertionPlan(text: text, cursorOffset: cursorOffset, retrigger: retrigger)
    }
}
