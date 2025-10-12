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
