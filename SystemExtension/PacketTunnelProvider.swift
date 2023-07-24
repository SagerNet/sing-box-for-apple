import Library
import NetworkExtension

class PacketTunnelProvider: ExtensionProvider {
    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let usernameObject = options?["username"] else {
            writeFatalError("missing start options")
            return
        }
        let username = usernameObject as! NSString
        FilePath.sharedDirectory = URL(filePath: "/Users/\(username)/Library/Group Containers/\(FilePath.groupName)")
        self.username = String(username)
        try await super.startTunnel(options: options)
    }
}
