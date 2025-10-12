import Libbox
import Library
import NetworkExtension
import System

class PacketTunnelProvider: ExtensionProvider {
    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let usernameObject = options?["username"] else {
            throw ExtensionStartupError("missing start options")
        }
        let username = usernameObject as! NSString
        FilePath.sharedDirectory = URL(filePath: "/Users/\(username)/Library/Group Containers/\(FilePath.groupName)")
        FilePath.iCloudDirectory = URL(filePath: "/Users/\(username)/Library/Mobile Documents/iCloud~\(FilePath.packageName.replacingOccurrences(of: ".", with: "~"))").appendingPathComponent("Documents", isDirectory: true)
        let databasePath = FilePath.sharedDirectory.appendingPathComponent("settings.db").relativePath
        if !FileManager.default.isReadableFile(atPath: databasePath) {
            do {
                let fd = try FileDescriptor.open(databasePath, .readOnly)
                try! fd.close()
                NSLog("Can access \(databasePath)")
            } catch {
                NSLog("Can't access \(databasePath): \(error.localizedDescription)")
            }
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 100)
            throw FullDiskAccessPermissionRequired.error
        }

        self.username = String(username)
        try await super.startTunnel(options: options)
    }
}
