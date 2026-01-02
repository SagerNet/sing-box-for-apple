import AVFoundation
import SwiftUI

public enum QRScanError: Error, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case scanFailed(Error)
    case invalidCode
    case qrsDecodeFailed

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
        case .qrsDecodeFailed:
            return String(localized: "Failed to decode QRS data")
        }
    }
}

public enum QRScanResult: Sendable {
    case qrCode(string: String, type: AVMetadataObject.ObjectType)
    case qrsData(Data)

    public var string: String? {
        switch self {
        case let .qrCode(string, _):
            return string
        case .qrsData:
            return nil
        }
    }
}
