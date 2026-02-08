import Foundation
import NetworkExtension

enum WidgetAppConfiguration {
    static let packageName: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BasePackageIdentifier") as? String else {
            fatalError("Missing BasePackageIdentifier in Info.plist")
        }
        return value
    }()

    static let appGroupID: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else {
            fatalError("Missing AppGroupIdentifier in Info.plist")
        }
        return value
    }()

    static var widgetControlKind: String {
        "\(packageName).widget.ServiceToggle"
    }
}

extension NEVPNStatus {
    var isStarted: Bool {
        switch self {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }
}

enum WidgetTunnelControl {
    static func currentIsStarted() async throws -> Bool {
        guard let manager = try await loadManager() else {
            return false
        }
        return manager.connection.status.isStarted
    }

    static func setStarted(_ started: Bool) async throws {
        guard let manager = try await loadManager() else {
            NSLog("[WidgetTunnelControl] No tunnel configuration found")
            throw NSError(domain: "WidgetTunnelControl", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Tunnel configuration not found",
            ])
        }

        if started {
            if manager.isEnabled == false {
                manager.isEnabled = true
                try await manager.saveToPreferences()
            }
            do {
                try manager.connection.startVPNTunnel()
            } catch {
                NSLog("[WidgetTunnelControl] startVPNTunnel failed: \(error.localizedDescription)")
                throw error
            }
        } else {
            manager.connection.stopVPNTunnel()
        }
    }

    private static func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first
    }
}
