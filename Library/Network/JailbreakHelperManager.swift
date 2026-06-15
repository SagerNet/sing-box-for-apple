#if JAILBREAK
    import Foundation

    public enum JailbreakHelperManager {
        public enum Status: Equatable {
            case running(version: String)
            case notRunning
        }

        public static var bundledVersion: String {
            Bundle.main.version
        }

        public static func status() -> Status {
            if let version = try? ShellHelperClient.shared.getVersion() {
                return .running(version: version)
            }
            return .notRunning
        }
    }
#endif
