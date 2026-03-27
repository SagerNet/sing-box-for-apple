import Foundation

public enum UpdateTrack: String, Codable, CaseIterable {
    case stable
    case beta

    public static var defaultForCurrentBuild: Self {
        Bundle.main.version.contains("-") ? .beta : .stable
    }

    public static func resolved(from rawValue: String) -> Self {
        guard !rawValue.isEmpty else {
            return defaultForCurrentBuild
        }
        return Self(rawValue: rawValue) ?? defaultForCurrentBuild
    }

    public func allows(_ updateInfo: UpdateInfo) -> Bool {
        switch self {
        case .stable:
            return !updateInfo.isPrerelease
        case .beta:
            return true
        }
    }
}
