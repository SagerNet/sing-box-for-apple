import Foundation

public struct TailscaleSSHPeerEntry: Identifiable {
    public var id: String {
        stableID
    }

    public let endpointTag: String
    public let displayName: String
    public let peerAddress: String
    public let stableID: String
    public let sshHostKeys: [String]

    public init(endpointTag: String, displayName: String, peerAddress: String, stableID: String, sshHostKeys: [String]) {
        self.endpointTag = endpointTag
        self.displayName = displayName
        self.peerAddress = peerAddress
        self.stableID = stableID
        self.sshHostKeys = sshHostKeys
    }

    @MainActor
    public func createSession() async -> TailscaleSSHPresentedSession {
        let usernames = await SharedPreferences.tailscaleSSHRememberedUsernames.get()
        let termTypes = await SharedPreferences.tailscaleSSHRememberedTerminalTypes.get()
        #if os(macOS)
            let forwardAgent = await SharedPreferences.tailscaleSSHForwardAgent.get()
        #else
            let forwardAgent = false
        #endif
        return TailscaleSSHPresentedSession(
            endpointTag: endpointTag,
            peerDisplayName: displayName,
            peerAddress: peerAddress,
            username: usernames[stableID] ?? "root",
            terminalType: termTypes[stableID] ?? "xterm-256color",
            hostKeys: sshHostKeys,
            forwardAgent: forwardAgent
        )
    }
}
