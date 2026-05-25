import Foundation

public struct TailscaleSSHPresentedSession: Identifiable, Codable, Hashable {
    public var id: UUID
    public let endpointTag: String
    public let peerHostName: String
    public let peerAddress: String
    public let username: String
    public let terminalType: String
    public let hostKeys: [String]

    public init(
        endpointTag: String,
        peerHostName: String,
        peerAddress: String,
        username: String,
        terminalType: String,
        hostKeys: [String]
    ) {
        id = UUID()
        self.endpointTag = endpointTag
        self.peerHostName = peerHostName
        self.peerAddress = peerAddress
        self.username = username
        self.terminalType = terminalType
        self.hostKeys = hostKeys
    }
}
