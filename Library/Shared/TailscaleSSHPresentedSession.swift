import Foundation

public struct TailscaleSSHPresentedSession: Identifiable, Codable, Hashable {
    public var id: UUID
    public let endpointTag: String
    public let peerDisplayName: String
    public let peerAddress: String
    public let username: String
    public let terminalType: String
    public let hostKeys: [String]
    public let forwardAgent: Bool

    public init(
        endpointTag: String,
        peerDisplayName: String,
        peerAddress: String,
        username: String,
        terminalType: String,
        hostKeys: [String],
        forwardAgent: Bool = false
    ) {
        id = UUID()
        self.endpointTag = endpointTag
        self.peerDisplayName = peerDisplayName
        self.peerAddress = peerAddress
        self.username = username
        self.terminalType = terminalType
        self.hostKeys = hostKeys
        self.forwardAgent = forwardAgent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        endpointTag = try container.decode(String.self, forKey: .endpointTag)
        peerDisplayName = try container.decode(String.self, forKey: .peerDisplayName)
        peerAddress = try container.decode(String.self, forKey: .peerAddress)
        username = try container.decode(String.self, forKey: .username)
        terminalType = try container.decode(String.self, forKey: .terminalType)
        hostKeys = try container.decode([String].self, forKey: .hostKeys)
        forwardAgent = try container.decodeIfPresent(Bool.self, forKey: .forwardAgent) ?? false
    }
}
