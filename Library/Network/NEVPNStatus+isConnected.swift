import Foundation
import NetworkExtension

public extension NEVPNStatus {
    var isEnabled: Bool {
        switch self {
        case .connecting, .connected, .disconnected, .reasserting:
            return true
        default:
            return false
        }
    }

    var isStarted: Bool {
        switch self {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }

    var isSwitchable: Bool {
        switch self {
        case .connected, .disconnected:
            return true
        default:
            return false
        }
    }

    var isConnected: Bool {
        switch self {
        case .connecting, .connected, .disconnecting, .reasserting:
            return true
        default:
            return false
        }
    }

    var isConnectedStrict: Bool {
        switch self {
        case .connected, .reasserting:
            return true
        default:
            return false
        }
    }
}
