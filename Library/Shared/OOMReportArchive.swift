import Foundation

public struct OOMReportMetadata: Codable, Sendable {
    public var source: String?
    public var bundleIdentifier: String?
    public var processName: String?
    public var processPath: String?
    public var startedAt: String?
    public var appVersion: String?
    public var appMarketingVersion: String?
    public var coreVersion: String?
    public var goVersion: String?
    public var recordedAt: String?
    public var memoryUsage: String?
    public var availableMemory: String?
    public var deviceOrigin: String?
}

public enum OOMReportArchive {
    static var reportsDirectory: URL {
        FilePath.workingDirectory.appendingPathComponent("oom_reports", isDirectory: true)
    }

    static func metadataURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.metadataFileName)
    }

    static func configURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.configFileName)
    }

    public static func readMetadata(for artifactURL: URL) -> OOMReportMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: artifactURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(OOMReportMetadata.self, from: data)
    }

    static func profileFiles(for artifactURL: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: artifactURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        let excluded: Set<String> = [ReportArchive.metadataFileName, ReportArchive.configFileName]
        return files
            .filter { !excluded.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func removeArtifact(at artifactURL: URL) {
        ReportArchive.removeArtifact(at: artifactURL)
    }

    static func reportDate(for artifactURL: URL) -> Date? {
        ReportArchive.parseArtifactDate(for: artifactURL)
    }
}
