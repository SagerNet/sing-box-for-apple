import Foundation

enum JSONPathStep: Equatable {
    case key(String)
    case index(Int)
}

struct JSONScalar {
    let isString: Bool
    let text: String
}

final class JSONContainerInfo {
    let step: JSONPathStep?
    let isObject: Bool
    let openOffset: Int
    var keys = Set<String>()
    var scalars = [String: JSONScalar]()

    init(step: JSONPathStep?, isObject: Bool, openOffset: Int) {
        self.step = step
        self.isObject = isObject
        self.openOffset = openOffset
    }
}

struct JSONDocumentTag {
    let path: [String]
    let value: String
}

struct JSONCursorContext {
    enum Kind {
        case objectKey(prefix: String, replaceStart: Int, hasOpenQuote: Bool)
        case value(step: JSONPathStep, prefix: String, replaceStart: Int, hasOpenQuote: Bool)
        case siblingSlot
    }

    let kind: Kind
    let containers: [JSONContainerInfo]
    let currentToken: String?
    let documentTags: [JSONDocumentTag]

    var allowsAutoShow: Bool {
        switch kind {
        case let .objectKey(prefix, _, hasOpenQuote):
            return hasOpenQuote || !prefix.isEmpty
        case let .value(_, prefix, _, hasOpenQuote):
            return hasOpenQuote || !prefix.isEmpty
        case .siblingSlot:
            return false
        }
    }

    var allowsNewlineAutoShow: Bool {
        switch kind {
        case let .objectKey(prefix, _, hasOpenQuote):
            return prefix.isEmpty && !hasOpenQuote
        case let .value(step, prefix, _, hasOpenQuote):
            guard case .index = step else {
                return false
            }
            return prefix.isEmpty && !hasOpenQuote
        case .siblingSlot:
            return true
        }
    }
}

private enum ScanPhase {
    case expectKey
    case expectColon
    case expectValue
    case expectCommaOrEnd
}

private final class ScanFrame {
    let info: JSONContainerInfo
    var phase: ScanPhase
    var currentKey: String?
    var nextIndex = 0

    init(info: JSONContainerInfo) {
        self.info = info
        phase = info.isObject ? .expectKey : .expectValue
    }
}

enum JSONCursorScanner {
    static func scan(text: String, cursor cursorOffset: Int) -> JSONCursorContext? {
        let string = text as NSString
        let length = string.length
        guard cursorOffset >= 0, cursorOffset <= length else {
            return nil
        }
        var buffer = [unichar](repeating: 0, count: length)
        string.getCharacters(&buffer)

        var stack = [ScanFrame]()
        var captured: (kind: JSONCursorContext.Kind, containers: [JSONContainerInfo], token: String?)?
        var attemptedBetweenTokens = false
        var documentTags = [JSONDocumentTag]()

        func captureBetweenTokens(at position: Int) {
            guard captured == nil, let frame = stack.last else {
                return
            }
            if frame.info.isObject {
                switch frame.phase {
                case .expectKey:
                    captured = (.objectKey(prefix: "", replaceStart: position, hasOpenQuote: false), stack.map(\.info), nil)
                case .expectValue:
                    if let key = frame.currentKey {
                        captured = (.value(step: .key(key), prefix: "", replaceStart: position, hasOpenQuote: false), stack.map(\.info), nil)
                    }
                case .expectCommaOrEnd:
                    captured = (.siblingSlot, stack.map(\.info), nil)
                case .expectColon:
                    break
                }
            } else {
                switch frame.phase {
                case .expectValue:
                    captured = (.value(step: .index(frame.nextIndex), prefix: "", replaceStart: position, hasOpenQuote: false), stack.map(\.info), nil)
                case .expectCommaOrEnd:
                    captured = (.siblingSlot, stack.map(\.info), nil)
                default:
                    break
                }
            }
        }

        func stepForChild() -> JSONPathStep? {
            guard let frame = stack.last else {
                return nil
            }
            if frame.info.isObject {
                frame.phase = .expectCommaOrEnd
                if let key = frame.currentKey {
                    return .key(key)
                }
                return nil
            }
            let index = frame.nextIndex
            frame.nextIndex += 1
            frame.phase = .expectCommaOrEnd
            return .index(index)
        }

        var i = 0
        while i < length {
            if !attemptedBetweenTokens, i >= cursorOffset {
                attemptedBetweenTokens = true
                captureBetweenTokens(at: cursorOffset)
            }
            let c = buffer[i]
            switch c {
            case unichar(UInt8(ascii: "{")), unichar(UInt8(ascii: "[")):
                let isObject = c == unichar(UInt8(ascii: "{"))
                let step = stack.isEmpty ? nil : stepForChild()
                stack.append(ScanFrame(info: JSONContainerInfo(step: step, isObject: isObject, openOffset: i)))
                i += 1
            case unichar(UInt8(ascii: "}")), unichar(UInt8(ascii: "]")):
                if !stack.isEmpty {
                    stack.removeLast()
                }
                i += 1
            case unichar(UInt8(ascii: ":")):
                if let frame = stack.last, frame.info.isObject, frame.phase == .expectColon {
                    frame.phase = .expectValue
                }
                i += 1
            case unichar(UInt8(ascii: ",")):
                if let frame = stack.last {
                    frame.phase = frame.info.isObject ? .expectKey : .expectValue
                }
                i += 1
            case unichar(UInt8(ascii: "/")):
                let commentStart = i
                if i + 1 < length, buffer[i + 1] == unichar(UInt8(ascii: "/")) {
                    i += 2
                    while i < length, buffer[i] != 0x0A, buffer[i] != 0x0D {
                        i += 1
                    }
                    if cursorOffset > commentStart, cursorOffset <= i {
                        return nil
                    }
                } else if i + 1 < length, buffer[i + 1] == unichar(UInt8(ascii: "*")) {
                    i += 2
                    var closed = false
                    while i < length {
                        if buffer[i] == unichar(UInt8(ascii: "*")), i + 1 < length, buffer[i + 1] == unichar(UInt8(ascii: "/")) {
                            i += 2
                            closed = true
                            break
                        }
                        i += 1
                    }
                    if cursorOffset > commentStart, !closed || cursorOffset < i {
                        return nil
                    }
                } else {
                    i += 1
                }
            case unichar(UInt8(ascii: "\"")):
                let quotePosition = i
                var content = String.UnicodeScalarView()
                var prefixUnitCount: Int?
                i += 1
                var closed = false
                while i < length {
                    if i >= cursorOffset, prefixUnitCount == nil {
                        prefixUnitCount = content.count
                    }
                    let ch = buffer[i]
                    if ch == unichar(UInt8(ascii: "\"")) {
                        closed = true
                        break
                    }
                    if ch == 0x0A || ch == 0x0D {
                        break
                    }
                    if ch == unichar(UInt8(ascii: "\\")), i + 1 < length {
                        let escaped = buffer[i + 1]
                        switch escaped {
                        case unichar(UInt8(ascii: "n")):
                            content.append("\n")
                        case unichar(UInt8(ascii: "t")):
                            content.append("\t")
                        case unichar(UInt8(ascii: "r")):
                            content.append("\r")
                        case unichar(UInt8(ascii: "u")):
                            if i + 5 < length {
                                let hex = String(utf16CodeUnits: Array(buffer[(i + 2) ... (i + 5)]), count: 4)
                                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                                    content.append(scalar)
                                }
                                i += 4
                            }
                        default:
                            if let scalar = Unicode.Scalar(escaped) {
                                content.append(scalar)
                            }
                        }
                        i += 2
                        continue
                    }
                    if let scalar = Unicode.Scalar(ch) {
                        content.append(scalar)
                    }
                    i += 1
                }
                let contentEnd = i
                if closed {
                    i += 1
                }
                let tokenText = String(content)
                let cursorInside = cursorOffset > quotePosition && cursorOffset <= contentEnd
                let prefix = cursorInside ? String(String.UnicodeScalarView(content.prefix(prefixUnitCount ?? content.count))) : ""
                handleToken(
                    stack: stack,
                    text: tokenText,
                    isString: true,
                    start: quotePosition,
                    cursorInside: cursorInside,
                    prefix: prefix,
                    captured: &captured,
                    documentTags: &documentTags
                )
            default:
                if isBareTokenCharacter(c) {
                    let start = i
                    var prefixEnd: Int?
                    while i < length, isBareTokenCharacter(buffer[i]) {
                        if i >= cursorOffset, prefixEnd == nil {
                            prefixEnd = i
                        }
                        i += 1
                    }
                    let tokenText = String(utf16CodeUnits: Array(buffer[start ..< i]), count: i - start)
                    let cursorInside = cursorOffset > start && cursorOffset <= i
                    let prefix: String
                    if cursorInside {
                        let end = prefixEnd ?? i
                        prefix = String(utf16CodeUnits: Array(buffer[start ..< end]), count: end - start)
                    } else {
                        prefix = ""
                    }
                    handleToken(
                        stack: stack,
                        text: tokenText,
                        isString: false,
                        start: start,
                        cursorInside: cursorInside,
                        prefix: prefix,
                        captured: &captured,
                        documentTags: &documentTags
                    )
                } else {
                    i += 1
                }
            }
        }
        if !attemptedBetweenTokens {
            captureBetweenTokens(at: cursorOffset)
        }
        guard let result = captured else {
            return nil
        }
        return JSONCursorContext(kind: result.kind, containers: result.containers, currentToken: result.token, documentTags: documentTags)
    }

    private static func handleToken(
        stack: [ScanFrame],
        text: String,
        isString: Bool,
        start: Int,
        cursorInside: Bool,
        prefix: String,
        captured: inout (kind: JSONCursorContext.Kind, containers: [JSONContainerInfo], token: String?)?,
        documentTags: inout [JSONDocumentTag]
    ) {
        guard let frame = stack.last else {
            return
        }
        if frame.info.isObject {
            switch frame.phase {
            case .expectKey, .expectColon, .expectCommaOrEnd:
                frame.currentKey = text
                frame.info.keys.insert(text)
                frame.phase = .expectColon
                if cursorInside, captured == nil {
                    captured = (.objectKey(prefix: prefix, replaceStart: start, hasOpenQuote: isString), stack.map(\.info), text)
                }
            case .expectValue:
                if let key = frame.currentKey {
                    frame.info.scalars[key] = JSONScalar(isString: isString, text: text)
                    if key == "tag", isString, case .index = frame.info.step,
                       let path = keyPath(of: stack.dropLast().map(\.info))
                    {
                        documentTags.append(JSONDocumentTag(path: path, value: text))
                    }
                    if cursorInside, captured == nil {
                        captured = (.value(step: .key(key), prefix: prefix, replaceStart: start, hasOpenQuote: isString), stack.map(\.info), text)
                    }
                }
                frame.phase = .expectCommaOrEnd
            }
        } else {
            if frame.phase == .expectValue {
                if cursorInside, captured == nil {
                    captured = (.value(step: .index(frame.nextIndex), prefix: prefix, replaceStart: start, hasOpenQuote: isString), stack.map(\.info), text)
                }
                frame.nextIndex += 1
                frame.phase = .expectCommaOrEnd
            }
        }
    }

    static func keyPath(of containers: [JSONContainerInfo]) -> [String]? {
        var path = [String]()
        for container in containers.dropFirst() {
            guard case let .key(name) = container.step else {
                return nil
            }
            path.append(name)
        }
        return path
    }

    private static func isBareTokenCharacter(_ c: unichar) -> Bool {
        switch c {
        case unichar(UInt8(ascii: "a")) ... unichar(UInt8(ascii: "z")),
             unichar(UInt8(ascii: "A")) ... unichar(UInt8(ascii: "Z")),
             unichar(UInt8(ascii: "0")) ... unichar(UInt8(ascii: "9")),
             unichar(UInt8(ascii: "_")), unichar(UInt8(ascii: "-")),
             unichar(UInt8(ascii: "+")), unichar(UInt8(ascii: ".")):
            return true
        default:
            return false
        }
    }
}
