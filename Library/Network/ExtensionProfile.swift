import Foundation
import NetworkExtension

public class ExtensionProfile: ObservableObject {
    private let manager: NEVPNManager
    private var connection: NEVPNConnection
    private var observer: Any?

    @Published public var status: NEVPNStatus

    public init(_ manager: NEVPNManager) {
        self.manager = manager
        connection = manager.connection
        status = manager.connection.status
    }

    deinit {
        unregister()
    }

    public func register() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }
            self.connection = notification.object as! NEVPNConnection
            self.status = self.connection.status
        }
    }

    private func unregister() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func start() async throws {
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try manager.connection.startVPNTunnel()
    }

    public func stop() {
        manager.connection.stopVPNTunnel()
    }

    public static func load() async throws -> ExtensionProfile? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if managers.isEmpty {
            return nil
        }
        let profile = ExtensionProfile(managers[0])
        return profile
    }

    public static func install() async throws {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "utun interface"
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "\(FilePath.packageName).extension"
        tunnelProtocol.serverAddress = "sing-box"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }
}
