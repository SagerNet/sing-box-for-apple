import Foundation

public struct PowerReportMetadata: Codable, Sendable {
    public var source: String?
    public var bundleIdentifier: String?
    public var processName: String?
    public var processPath: String?
    public var startedAt: String?
    public var appVersion: String?
    public var appMarketingVersion: String?
    public var coreVersion: String?
    public var goVersion: String?
    public var deviceOrigin: String?
}

public enum PowerReportArchive {
    static let timelineFileName = "timeline.jsonl"
    static let eventsFileName = "events.jsonl"

    static var reportsDirectory: URL {
        FilePath.workingDirectory.appendingPathComponent("power_reports", isDirectory: true)
    }

    static func metadataURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.metadataFileName)
    }

    static func configURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.configFileName)
    }

    static func timelineURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(timelineFileName)
    }

    static func eventsURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(eventsFileName)
    }

    static func goLogURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.goLogFileName)
    }

    public static func readMetadata(for artifactURL: URL) -> PowerReportMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: artifactURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(PowerReportMetadata.self, from: data)
    }

    static func profileFiles(for artifactURL: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: artifactURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        let excluded: Set<String> = [ReportArchive.metadataFileName, ReportArchive.configFileName, timelineFileName, eventsFileName, ReportArchive.goLogFileName]
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
