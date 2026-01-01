import AVFoundation
import SwiftUI

public enum QRScanError: Error, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case scanFailed(Error)
    case invalidCode

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return String(localized: "Camera is not available")
        case .permissionDenied:
            return String(localized: "Camera access denied")
        case let .scanFailed(error):
            return error.localizedDescription
        case .invalidCode:
            return String(localized: "Invalid QR code")
        }
    }
}

public struct QRScanResult: Sendable {
    public let string: String
    public let type: AVMetadataObject.ObjectType

    public init(string: String, type: AVMetadataObject.ObjectType) {
        self.string = string
        self.type = type
    }
}
