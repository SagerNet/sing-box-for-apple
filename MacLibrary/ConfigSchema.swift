import Foundation
import Libbox

enum SchemaValueShape {
    case array
    case object
    case string
    case scalar
    case ambiguous
}

struct CompletionItem: Equatable {
    enum Kind {
        case property
        case value
    }

    let kind: Kind
    let label: String
    let insertText: String
    let detail: String?
    let isString: Bool
    let valueShape: SchemaValueShape?
    var arrayExample: [String]?
}

private struct SchemaVariant {
    var properties = [String: Any]()
    var propertyOrder = [String]()
    var required = Set<String>()
    var additional = [Any]()
}

struct OrderedJSONParser {
    static let propertyOrderKey = "__property_order__"

    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ data: Data) -> Any? {
        var parser = OrderedJSONParser(data)
        return parser.parseValue()
    }

    private init(_ data: Data) {
        bytes = [UInt8](data)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            default:
                return
            }
        }
    }

    private mutating func parseValue() -> Any? {
        skipWhitespace()
        guard index < bytes.count else {
            return nil
        }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            return parseObject()
        case UInt8(ascii: "["):
            return parseArray()
        case UInt8(ascii: "\""):
            return parseString()
        case UInt8(ascii: "t"):
            return parseLiteral("true", NSNumber(value: true))
        case UInt8(ascii: "f"):
            return parseLiteral("false", NSNumber(value: false))
        case UInt8(ascii: "n"):
            return parseLiteral("null", NSNull())
        default:
            return parseNumber()
        }
    }

    private mutating func parseObject() -> Any? {
        index += 1
        var object = [String: Any]()
        var order = [String]()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            object[Self.propertyOrderKey] = order
            return object
        }
        while index < bytes.count {
            skipWhitespace()
            guard let key = parseString() else {
                return nil
            }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                return nil
            }
            index += 1
            guard let value = parseValue() else {
                return nil
            }
            object[key] = value
            order.append(key)
            skipWhitespace()
            guard index < bytes.count else {
                return nil
            }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                object[Self.propertyOrderKey] = order
                return object
            }
            return nil
        }
        return nil
    }

    private mutating func parseArray() -> Any? {
        index += 1
        var array = [Any]()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return array
        }
        while index < bytes.count {
            guard let value = parseValue() else {
                return nil
            }
            array.append(value)
            skipWhitespace()
            guard index < bytes.count else {
                return nil
            }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return array
            }
            return nil
        }
        return nil
    }

    private mutating func parseString() -> String? {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
            return nil
        }
        index += 1
        var result = [UInt8]()
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                return String(bytes: result, encoding: .utf8)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else {
                    return nil
                }
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    result.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"):
                    result.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"):
                    result.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"):
                    result.append(0x08)
                case UInt8(ascii: "f"):
                    result.append(0x0C)
                case UInt8(ascii: "n"):
                    result.append(0x0A)
                case UInt8(ascii: "r"):
                    result.append(0x0D)
                case UInt8(ascii: "t"):
                    result.append(0x09)
                case UInt8(ascii: "u"):
                    guard var value = parseHexEscape() else {
                        return nil
                    }
                    if value >= 0xD800, value <= 0xDBFF,
                       index + 6 < bytes.count, bytes[index + 1] == UInt8(ascii: "\\"), bytes[index + 2] == UInt8(ascii: "u")
                    {
                        index += 2
                        guard let low = parseHexEscape(), low >= 0xDC00, low <= 0xDFFF else {
                            return nil
                        }
                        value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(value) else {
                        return nil
                    }
                    result.append(contentsOf: Array(String(scalar).utf8))
                default:
                    return nil
                }
                index += 1
            } else {
                result.append(byte)
                index += 1
            }
        }
        return nil
    }

    private mutating func parseHexEscape() -> UInt32? {
        guard index + 4 < bytes.count else {
            return nil
        }
        guard let hex = String(bytes: bytes[(index + 1) ... (index + 4)], encoding: .utf8), let value = UInt32(hex, radix: 16) else {
            return nil
        }
        index += 4
        return value
    }

    private mutating func parseLiteral(_ literal: String, _ value: Any) -> Any? {
        let literalBytes = Array(literal.utf8)
        guard index + literalBytes.count <= bytes.count else {
            return nil
        }
        for (offset, byte) in literalBytes.enumerated() where bytes[index + offset] != byte {
            return nil
        }
        index += literalBytes.count
        return value
    }

    private mutating func parseNumber() -> Any? {
        let start = index
        var isFloatingPoint = false
        scanning: while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"):
                index += 1
            case UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"):
                isFloatingPoint = true
                index += 1
            default:
                break scanning
            }
        }
        return finishNumber(start: start, isFloatingPoint: isFloatingPoint)
    }

    private func finishNumber(start: Int, isFloatingPoint: Bool) -> Any? {
        guard index > start, let text = String(bytes: bytes[start ..< index], encoding: .utf8) else {
            return nil
        }
        if !isFloatingPoint, let integer = Int64(text) {
            return NSNumber(value: integer)
        }
        guard let double = Double(text) else {
            return nil
        }
        return NSNumber(value: double)
    }
}

final class ConfigSchema: @unchecked Sendable {
    static let shared = ConfigSchema()

    private static let referencePaths: [String: [[String]]] = [
        "outbound": [["outbounds"], ["endpoints"]],
        "inbound": [["inbounds"]],
        "dns_server": [["dns", "servers"]],
        "rule_set": [["route", "rule_set"]],
        "certificate_provider": [["certificate_providers"]],
        "http_client": [["http_clients"]],
        "network_namespace": [["network_namespaces"]],
    ]

    private let lock = NSLock()
    private var loadAttempted = false
    private var rootSchema: [String: Any]?
    private var referenceCache = [String: [String: Any]]()
    private var variantCache = [String: [SchemaVariant]]()
    private var itemSchemaCache = [String: [Any]]()

    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            _ = shared.load()
        }
    }

    func load() -> [String: Any]? {
        lock.lock()
        defer {
            lock.unlock()
        }
        if !loadAttempted {
            loadAttempted = true
            var error: NSError?
            let schemaString = LibboxGenerateConfigSchema(&error)?.value
            if error == nil, let schemaString, let data = schemaString.data(using: .utf8) {
                rootSchema = OrderedJSONParser.parse(data) as? [String: Any]
            }
        }
        return rootSchema
    }

    func completions(for context: JSONCursorContext) -> [CompletionItem] {
        guard let root = load() else {
            return []
        }
        let containers = context.containers
        guard !containers.isEmpty else {
            return []
        }
        var schemas: [Any] = [root]
        for index in 1 ..< containers.count {
            let parentInfo = containers[index - 1]
            switch containers[index].step {
            case let .key(name):
                schemas = propertySchemas(named: name, in: schemas, scalars: parentInfo.scalars, excludeKey: nil)
            case .index:
                schemas = schemas.flatMap { itemSchemas($0, depth: 0) }
            case nil:
                break
            }
            if schemas.isEmpty {
                return []
            }
        }
        guard let innermost = containers.last else {
            return []
        }
        switch context.kind {
        case let .objectKey(prefix, _, _):
            return keyCompletions(in: schemas, container: innermost, prefix: prefix, currentToken: context.currentToken)
        case let .value(step, prefix, _, hasOpenQuote):
            let valueSchemas: [Any]
            let isArrayItem: Bool
            switch step {
            case let .key(name):
                valueSchemas = propertySchemas(named: name, in: schemas, scalars: innermost.scalars, excludeKey: name)
                isArrayItem = false
            case .index:
                valueSchemas = schemas.flatMap { itemSchemas($0, depth: 0) }
                isArrayItem = true
            }
            return valueCompletions(
                in: valueSchemas,
                prefix: prefix,
                includeForms: !hasOpenQuote && prefix.isEmpty,
                allowSingleContainerForms: isArrayItem,
                context: context
            )
        case .siblingSlot:
            if innermost.isObject {
                return keyCompletions(in: schemas, container: innermost, prefix: "", currentToken: nil)
            }
            return valueCompletions(
                in: schemas.flatMap { itemSchemas($0, depth: 0) },
                prefix: "",
                includeForms: true,
                allowSingleContainerForms: true,
                context: context
            )
        }
    }

    static func shouldAutoDismiss(context: JSONCursorContext, items: [CompletionItem]) -> Bool {
        guard items.count == 1, let item = items.first, item.kind == .value, item.valueShape == nil else {
            return false
        }
        if case let .value(_, prefix, _, _) = context.kind {
            return item.label == prefix
        }
        return false
    }

    private func keyCompletions(in schemas: [Any], container: JSONContainerInfo, prefix: String, currentToken: String?) -> [CompletionItem] {
        var presentKeys = container.keys
        if let currentToken {
            presentKeys.remove(currentToken)
        }
        var variants = schemas.flatMap { expandVariants($0, depth: 0) }
        variants = narrow(variants, scalars: container.scalars)
        let missingDiscriminators = discriminatorKeys(in: variants).filter { container.scalars[$0] == nil }.sorted()
        var names = [String]()
        var schemasByName = [String: Any]()
        func collect(from variantList: [SchemaVariant]) {
            for variant in variantList {
                for name in variant.propertyOrder {
                    guard let propertySchema = variant.properties[name] else {
                        continue
                    }
                    if presentKeys.contains(name) {
                        continue
                    }
                    if schemasByName[name] == nil {
                        schemasByName[name] = propertySchema
                        names.append(name)
                    }
                }
            }
        }
        if missingDiscriminators.isEmpty {
            collect(from: variants)
        } else {
            let candidates = variants.filter { variant in
                missingDiscriminators.allSatisfy { admitsAbsence(of: $0, in: variant) }
            }
            if !candidates.isEmpty {
                collect(from: candidates)
            }
            for discriminator in missingDiscriminators {
                if schemasByName[discriminator] != nil || presentKeys.contains(discriminator) {
                    continue
                }
                guard let sample = variants.first(where: { $0.properties[discriminator] != nil })?.properties[discriminator] else {
                    continue
                }
                schemasByName[discriminator] = sample
                names.append(discriminator)
            }
        }
        if !prefix.isEmpty {
            names = names.filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
        }
        return names.map { name in
            CompletionItem(
                kind: .property,
                label: name,
                insertText: name,
                detail: schemasByName[name].flatMap { typeDescription($0, depth: 0) },
                isString: true,
                valueShape: schemasByName[name].map { valueShape($0, depth: 0) }
            )
        }
    }

    private func referenceTags(kind: String, context: JSONCursorContext) -> [String] {
        guard let paths = ConfigSchema.referencePaths[kind] else {
            return []
        }
        var excluded = Set<String>()
        let containers = context.containers
        for index in 1 ..< containers.count {
            guard case .index = containers[index].step,
                  let path = JSONCursorScanner.keyPath(of: Array(containers[..<index])),
                  paths.contains(path),
                  let tag = containers[index].scalars["tag"], tag.isString
            else {
                continue
            }
            excluded.insert(tag.text)
        }
        return context.documentTags
            .filter { paths.contains($0.path) && !excluded.contains($0.value) }
            .map(\.value)
    }

    private func valueCompletions(in schemas: [Any], prefix: String, includeForms: Bool, allowSingleContainerForms: Bool, context: JSONCursorContext) -> [CompletionItem] {
        var enumItems = [CompletionItem]()
        var exampleItems = [CompletionItem]()
        var seen = Set<String>()
        var formKinds = Set<String>()
        var offeredForms = Set<SchemaValueShape>()
        func add(_ label: String, isString: Bool, detail: String?, to items: inout [CompletionItem]) {
            if seen.insert(label).inserted {
                items.append(CompletionItem(kind: .value, label: label, insertText: label, detail: detail, isString: isString, valueShape: nil))
            }
        }
        func addValue(_ value: Any, detail: String?, to items: inout [CompletionItem]) {
            if let stringValue = value as? String {
                if stringValue.isEmpty {
                    return
                }
                add(stringValue, isString: true, detail: detail, to: &items)
            } else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    add(number.boolValue ? "true" : "false", isString: false, detail: detail, to: &items)
                } else {
                    add(number.stringValue, isString: false, detail: detail, to: &items)
                }
            } else if value is NSNull {
                add("null", isString: false, detail: detail, to: &items)
            }
        }
        func collect(_ schema: Any, depth: Int) {
            guard depth < 32, let dict = dereference(schema, depth: depth) else {
                return
            }
            let enumValues = dict["enum"] as? [Any]
            let examples = dict["examples"] as? [Any]
            if let constValue = dict["const"] {
                addValue(constValue, detail: nil, to: &enumItems)
            }
            enumValues?.forEach { addValue($0, detail: nil, to: &enumItems) }
            if let referenceKind = dict["x-tag-reference"] as? String {
                for tag in referenceTags(kind: referenceKind, context: context) {
                    add(tag, isString: true, detail: referenceKind, to: &enumItems)
                }
            }
            examples?.forEach { addValue($0, detail: "example", to: &exampleItems) }
            if includeForms, !allowSingleContainerForms, let examples {
                for example in examples {
                    guard let arrayValue = example as? [Any] else {
                        continue
                    }
                    let elements = arrayValue.compactMap { $0 as? String }
                    guard elements.count == arrayValue.count, !elements.isEmpty else {
                        continue
                    }
                    let compact = "[" + elements.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
                    guard seen.insert(compact).inserted else {
                        continue
                    }
                    var label = compact
                    if label.count > 48 {
                        label = String(label.prefix(46)) + "…]"
                    }
                    exampleItems.append(CompletionItem(kind: .value, label: label, insertText: compact, detail: "example", isString: false, valueShape: nil, arrayExample: elements))
                }
            }
            let typeName = dict["type"] as? String
            switch typeName {
            case "array":
                formKinds.insert("array")
                offeredForms.insert(.array)
            case "object":
                formKinds.insert("object")
                offeredForms.insert(.object)
            case "string":
                if enumValues == nil, examples == nil, dict["const"] == nil {
                    formKinds.insert("string")
                    offeredForms.insert(.string)
                } else {
                    formKinds.insert("string-values")
                }
            case "boolean":
                formKinds.insert("boolean")
                add("true", isString: false, detail: nil, to: &enumItems)
                add("false", isString: false, detail: nil, to: &enumItems)
            case "integer", "number":
                formKinds.insert("number")
            default:
                if dict["properties"] != nil || dict["additionalProperties"] is [String: Any] {
                    formKinds.insert("object")
                    offeredForms.insert(.object)
                }
            }
            for keyword in ["oneOf", "anyOf", "allOf"] {
                for branch in dict[keyword] as? [Any] ?? [] {
                    collect(branch, depth: depth + 1)
                }
            }
        }
        for schema in schemas {
            collect(schema, depth: 0)
        }
        var items = enumItems + exampleItems
        if !prefix.isEmpty {
            items = items.filter { $0.label.lowercased().hasPrefix(prefix.lowercased()) }
        }
        if includeForms {
            let multiForm = formKinds.count >= 2
            for shape in [SchemaValueShape.array, .object, .string] where offeredForms.contains(shape) {
                if !multiForm {
                    guard allowSingleContainerForms, shape != .string else {
                        continue
                    }
                }
                let label: String
                let detail: String
                switch shape {
                case .array:
                    label = "[]"
                    detail = "array"
                case .object:
                    label = "{}"
                    detail = "object"
                default:
                    label = "\"\""
                    detail = "string"
                }
                items.append(CompletionItem(kind: .value, label: label, insertText: label, detail: detail, isString: false, valueShape: shape))
            }
        }
        return items
    }

    private func propertySchemas(named name: String, in schemas: [Any], scalars: [String: JSONScalar], excludeKey: String?) -> [Any] {
        var narrowScalars = scalars
        if let excludeKey {
            narrowScalars.removeValue(forKey: excludeKey)
        }
        var variants = schemas.flatMap { expandVariants($0, depth: 0) }
        variants = narrow(variants, scalars: narrowScalars)
        let result = variants.compactMap { $0.properties[name] }
        if !result.isEmpty {
            return result
        }
        return variants.flatMap(\.additional)
    }

    private func valueShape(_ schema: Any, depth: Int) -> SchemaValueShape {
        guard depth < 16, let dict = dereference(schema, depth: 0) else {
            return .ambiguous
        }
        if let enumValues = dict["enum"] as? [Any] {
            return enumValues.allSatisfy { $0 is String } ? .string : .scalar
        }
        if let constValue = dict["const"] {
            return constValue is String ? .string : .scalar
        }
        if let type = dict["type"] as? String {
            switch type {
            case "array":
                return .array
            case "object":
                return .object
            case "string":
                return .string
            case "boolean", "integer", "number":
                return .scalar
            default:
                return .ambiguous
            }
        }
        var shapes = Set<SchemaValueShape>()
        for keyword in ["oneOf", "anyOf", "allOf"] {
            for branch in dict[keyword] as? [Any] ?? [] {
                shapes.insert(valueShape(branch, depth: depth + 1))
            }
        }
        if shapes.count == 1, let shape = shapes.first {
            return shape
        }
        if shapes.isEmpty, dict["properties"] != nil {
            return .object
        }
        return .ambiguous
    }

    private func itemSchemas(_ schema: Any, depth: Int) -> [Any] {
        let cacheKey = (schema as? [String: Any])?["$ref"] as? String
        if let cacheKey, let cached = itemSchemaCache[cacheKey] {
            return cached
        }
        guard depth < 32, let dict = dereference(schema, depth: depth) else {
            return []
        }
        var result = [Any]()
        if let items = dict["items"] {
            result.append(items)
        }
        for keyword in ["oneOf", "anyOf", "allOf"] {
            for branch in dict[keyword] as? [Any] ?? [] {
                result += itemSchemas(branch, depth: depth + 1)
            }
        }
        if let cacheKey {
            itemSchemaCache[cacheKey] = result
        }
        return result
    }

    private func expandVariants(_ schema: Any, depth: Int) -> [SchemaVariant] {
        let cacheKey = (schema as? [String: Any])?["$ref"] as? String
        if let cacheKey, let cached = variantCache[cacheKey] {
            return cached
        }
        guard depth < 32, let dict = dereference(schema, depth: depth) else {
            return []
        }
        var base = SchemaVariant()
        var isObjectLike = false
        if var properties = dict["properties"] as? [String: Any] {
            if let order = properties.removeValue(forKey: OrderedJSONParser.propertyOrderKey) as? [String] {
                base.propertyOrder = order
            } else {
                base.propertyOrder = Array(properties.keys)
            }
            base.properties = properties
            isObjectLike = true
        }
        if let required = dict["required"] as? [Any] {
            base.required = Set(required.compactMap { $0 as? String })
        }
        if let additional = dict["additionalProperties"] as? [String: Any] {
            base.additional = [additional]
            isObjectLike = true
        }
        if (dict["type"] as? String) == "object" {
            isObjectLike = true
        }
        var result = [base]
        if let allOf = dict["allOf"] as? [Any] {
            for member in allOf {
                let memberVariants = expandVariants(member, depth: depth + 1)
                if memberVariants.isEmpty {
                    continue
                }
                isObjectLike = true
                result = result.flatMap { existing in
                    memberVariants.map { merge(existing, $0) }
                }
            }
        }
        var branchVariants = [SchemaVariant]()
        for keyword in ["oneOf", "anyOf"] {
            for branch in dict[keyword] as? [Any] ?? [] {
                branchVariants += expandVariants(branch, depth: depth + 1)
            }
        }
        if !branchVariants.isEmpty {
            isObjectLike = true
            result = result.flatMap { existing in
                branchVariants.map { merge(existing, $0) }
            }
        }
        let expanded = isObjectLike ? result : []
        if let cacheKey {
            variantCache[cacheKey] = expanded
        }
        return expanded
    }

    private func merge(_ left: SchemaVariant, _ right: SchemaVariant) -> SchemaVariant {
        var merged = left
        merged.properties.merge(right.properties) { _, new in new }
        for name in right.propertyOrder where !merged.propertyOrder.contains(name) {
            merged.propertyOrder.append(name)
        }
        merged.required.formUnion(right.required)
        merged.additional += right.additional
        return merged
    }

    private func discriminatorKeys(in variants: [SchemaVariant]) -> [String] {
        guard variants.count > 1 else {
            return []
        }
        var allowedSets = [String: [Set<String>]]()
        var definedCounts = [String: Int]()
        for variant in variants {
            for (name, propertySchema) in variant.properties {
                definedCounts[name, default: 0] += 1
                guard let dict = dereference(propertySchema, depth: 0) else {
                    continue
                }
                var allowed: [Any]?
                if let constValue = dict["const"] {
                    allowed = [constValue]
                } else if let enumValues = dict["enum"] as? [Any] {
                    allowed = enumValues
                }
                guard let allowed else {
                    continue
                }
                allowedSets[name, default: []].append(Set(allowed.compactMap(constString)))
            }
        }
        return allowedSets.compactMap { name, sets in
            guard sets.count >= 2, sets.count == definedCounts[name], Set(sets).count > 1 else {
                return nil
            }
            return name
        }
    }

    private func admitsAbsence(of key: String, in variant: SchemaVariant) -> Bool {
        guard let propertySchema = variant.properties[key] else {
            return true
        }
        if !variant.required.contains(key) {
            return true
        }
        guard let dict = dereference(propertySchema, depth: 0), let enumValues = dict["enum"] as? [Any] else {
            return false
        }
        return enumValues.contains { ($0 as? String) == "" }
    }

    private func constString(_ value: Any) -> String? {
        if let stringValue = value as? String {
            return stringValue
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return nil
    }

    private func narrow(_ variants: [SchemaVariant], scalars: [String: JSONScalar]) -> [SchemaVariant] {
        guard !scalars.isEmpty else {
            return variants
        }
        let narrowed = variants.filter { variant in
            for (key, scalar) in scalars {
                guard let propertySchema = variant.properties[key], let dict = dereference(propertySchema, depth: 0) else {
                    continue
                }
                var allowed = [Any]()
                if let constValue = dict["const"] {
                    allowed = [constValue]
                } else if let enumValues = dict["enum"] as? [Any] {
                    allowed = enumValues
                }
                if allowed.isEmpty {
                    continue
                }
                if !allowed.contains(where: { scalarMatches(scalar, $0) }) {
                    return false
                }
            }
            return true
        }
        return narrowed.isEmpty ? variants : narrowed
    }

    private func scalarMatches(_ scalar: JSONScalar, _ value: Any) -> Bool {
        if let stringValue = value as? String {
            return scalar.isString && scalar.text == stringValue
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return !scalar.isString && scalar.text == (number.boolValue ? "true" : "false")
            }
            return !scalar.isString && scalar.text == number.stringValue
        }
        return false
    }

    private func typeDescription(_ schema: Any, depth: Int) -> String? {
        guard depth < 8, let dict = dereference(schema, depth: 0) else {
            return nil
        }
        if dict["const"] != nil || dict["enum"] != nil {
            return "enum"
        }
        if let type = dict["type"] as? String {
            return type
        }
        var parts = [String]()
        for keyword in ["oneOf", "anyOf", "allOf"] {
            for branch in dict[keyword] as? [Any] ?? [] {
                if let description = typeDescription(branch, depth: depth + 1), !parts.contains(description) {
                    parts.append(description)
                }
            }
        }
        if parts.isEmpty {
            return dict["properties"] != nil ? "object" : nil
        }
        return parts.joined(separator: " | ")
    }

    private func dereference(_ schema: Any, depth: Int) -> [String: Any]? {
        guard depth < 32, var dict = schema as? [String: Any] else {
            return nil
        }
        var hops = 0
        while let ref = dict["$ref"] as? String, hops < 16 {
            guard let target = lookupReference(ref) else {
                return dict
            }
            dict = target
            hops += 1
        }
        return dict
    }

    private func lookupReference(_ ref: String) -> [String: Any]? {
        if let cached = referenceCache[ref] {
            return cached
        }
        guard let root = rootSchema, ref.hasPrefix("#") else {
            return nil
        }
        var current: Any = root
        let components = ref.dropFirst().split(separator: "/")
        for component in components {
            let name = component
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard let dict = current as? [String: Any], let next = dict[name] else {
                return nil
            }
            current = next
        }
        let resolved = current as? [String: Any]
        if let resolved {
            referenceCache[ref] = resolved
        }
        return resolved
    }
}
