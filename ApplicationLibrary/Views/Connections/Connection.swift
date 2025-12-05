import Foundation

public struct Connection: Codable, Hashable, Equatable {
    public let id: String
    public let inbound: String
    public let inboundType: String
    public let ipVersion: Int32
    public let network: String
    public let source: String
    public let destination: String
    public let domain: String
    public let displayDestination: String
    public let protocolName: String
    public let user: String
    public let fromOutbound: String
    public let createdAt: Date
    public let closedAt: Date?
    public var upload: Int64
    public var download: Int64
    public var uploadTotal: Int64
    public var downloadTotal: Int64
    public let rule: String
    public let outbound: String
    public let outboundType: String
    public let chain: [String]

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(upload)
        hasher.combine(download)
        hasher.combine(uploadTotal)
        hasher.combine(downloadTotal)
        hasher.combine(closedAt)
    }

    public static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id &&
            lhs.upload == rhs.upload &&
            lhs.download == rhs.download &&
            lhs.uploadTotal == rhs.uploadTotal &&
            lhs.downloadTotal == rhs.downloadTotal &&
            lhs.closedAt == rhs.closedAt
    }

    func performSearch(_ content: String) -> Bool {
        for item in content.components(separatedBy: " ") {
            let itemSep = item.components(separatedBy: ":")
            if itemSep.count == 2 {
                if !performSearchType(type: itemSep[0], value: itemSep[1]) {
                    return false
                }
                continue
            }
            if !performSearchPlain(item) {
                return false
            }
        }
        return true
    }

    private func performSearchPlain(_ content: String) -> Bool {
        destination.contains(content) ||
            domain.contains(content)
    }

    private func performSearchType(type: String, value: String) -> Bool {
        switch type {
        // TODO: impl more
        case "network":
            return network == value
        case "inbound":
            return inbound.contains(value)
        case "inbound.type":
            return inboundType == value
        case "source":
            return source.contains(value)
        case "destination":
            return destination.contains(value)
        default:
            return false
        }
    }
}
