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
        FilePath.iCloudDirectory = URL(filePath: "/Users/\(username)/Library/Mobile Documents/iCloud~\(FilePath.packageName.replacingOccurrences(of: ".", with: "~"))").appendingPathComponent("Documents", isDirectory: true)
        self.username = String(username)
        try await super.startTunnel(options: options)
    }
}
