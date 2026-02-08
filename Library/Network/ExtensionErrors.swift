import Foundation

public enum FullDiskAccessPermissionRequired: Error {
    case error
}

public class ExtensionStartupError: Error {
    let message: String

    public init(_ message: String) {
        self.message = message
    }
}

extension ExtensionStartupError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension ExtensionStartupError: CustomNSError {
    public static var errorDomain: String {
        "ExtensionStartupError"
    }

    public var errorCode: Int {
        1
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: message]
    }
}
