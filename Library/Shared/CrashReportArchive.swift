import Foundation

public struct CrashReportMetadata: Codable, Sendable {
    public var source: String?
    public var bundleIdentifier: String?
    public var processName: String?
    public var processPath: String?
    public var startedAt: String?
    public var appVersion: String?
    public var appMarketingVersion: String?
    public var coreVersion: String?
    public var goVersion: String?
    public var crashedAt: String?
    public var signalName: String?
    public var signalCode: String?
    public var exceptionName: String?
    public var exceptionReason: String?
    public var deviceOrigin: String?

    public init(
        source: String? = nil,
        bundleIdentifier: String? = nil,
        processName: String? = nil,
        processPath: String? = nil,
        startedAt: String? = nil,
        appVersion: String? = nil,
        appMarketingVersion: String? = nil,
        coreVersion: String? = nil,
        goVersion: String? = nil,
        crashedAt: String? = nil,
        signalName: String? = nil,
        signalCode: String? = nil,
        exceptionName: String? = nil,
        exceptionReason: String? = nil,
        deviceOrigin: String? = nil
    ) {
        self.source = source
        self.bundleIdentifier = bundleIdentifier
        self.processName = processName
        self.processPath = processPath
        self.startedAt = startedAt
        self.appVersion = appVersion
        self.appMarketingVersion = appMarketingVersion
        self.coreVersion = coreVersion
        self.goVersion = goVersion
        self.crashedAt = crashedAt
        self.signalName = signalName
        self.signalCode = signalCode
        self.exceptionName = exceptionName
        self.exceptionReason = exceptionReason
        self.deviceOrigin = deviceOrigin
    }
}

public struct CrashReportArtifactContents {
    public var goLog: String?
    public var nativeLog: String?
    public var configContent: String?

    public init(goLog: String? = nil, nativeLog: String? = nil, configContent: String? = nil) {
        self.goLog = goLog
        self.nativeLog = nativeLog
        self.configContent = configContent
    }

    public var isEmpty: Bool {
        let goBody = goLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nativeBody = nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return goBody.isEmpty && nativeBody.isEmpty
    }
}

public enum ReportArchive {
    public static let readMarkerFileName = ".read"
    public static let metadataFileName = "metadata.json"
    public static let configFileName = "configuration.json"
    public static let tvOSDeviceOrigin = "tvOS"

    public static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public static func parseArtifactDate(for artifactURL: URL) -> Date? {
        let name = artifactURL.lastPathComponent
        let components = name.components(separatedBy: "-")
        let baseName: String
        if components.count > 5, let suffix = components.last, Int(suffix) != nil {
            baseName = components.dropLast().joined(separator: "-")
        } else {
            baseName = components.joined(separator: "-")
        }
        return timestampFormatter.date(from: baseName)
    }

    public static func nextAvailableArtifactURL(in directory: URL, for date: Date) -> URL {
        let baseName = timestampFormatter.string(from: date)
        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let artifactURL = directory.appendingPathComponent(baseName + suffix, isDirectory: true)
            if !FileManager.default.fileExists(atPath: artifactURL.path) {
                return artifactURL
            }
            index += 1
        }
    }

    static func removeArtifact(at artifactURL: URL) {
        try? FileManager.default.removeItem(at: artifactURL)
    }
}

public enum CrashReportArchive {
    static let pendingNativeCrashDirectoryName = "native_crash_pending"
    static let pendingNativeCrashStorageDirectoryName = "com.plausiblelabs.crashreporter.data"
    static let pendingNativeCrashReportFileName = "live_report.plcrash"
    static let goLogFileName = "go.log"
    static let nativeLogFileName = "native.log"

    static var crashReportsDirectory: URL {
        FilePath.workingDirectory.appendingPathComponent("crash_reports", isDirectory: true)
    }

    static var pendingNativeCrashBaseDirectory: URL {
        FilePath.sharedDirectory.appendingPathComponent(pendingNativeCrashDirectoryName, isDirectory: true)
    }

    static func metadataURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.metadataFileName)
    }

    static func goLogURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(goLogFileName)
    }

    static func nativeLogURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(nativeLogFileName)
    }

    static func configURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(ReportArchive.configFileName)
    }

    static func pendingNativeCrashReportURL(bundleIdentifier: String) -> URL {
        pendingNativeCrashReportURL(basePath: pendingNativeCrashBaseDirectory, bundleIdentifier: bundleIdentifier)
    }

    public static func pendingNativeCrashReportURL(basePath: URL, bundleIdentifier: String) -> URL {
        basePath
            .appendingPathComponent(pendingNativeCrashStorageDirectoryName, isDirectory: true)
            .appendingPathComponent(bundleIdentifier.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
            .appendingPathComponent(pendingNativeCrashReportFileName)
    }

    public static func writeArchivedReport(contents: CrashReportArtifactContents, date: Date, metadata: CrashReportMetadata) throws -> URL {
        guard !contents.isEmpty else {
            throw NSError(domain: "CrashReportArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty crash report"])
        }

        let dir = crashReportsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifactURL = nextAvailableArtifactURL(for: date)
        try rewriteArchivedReport(at: artifactURL, contents: contents, metadata: metadata)
        return artifactURL
    }

    static func rewriteArchivedReport(at artifactURL: URL, contents: CrashReportArtifactContents, metadata: CrashReportMetadata) throws {
        guard !contents.isEmpty else {
            throw NSError(domain: "CrashReportArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty crash report"])
        }

        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)

        if let goLog = contents.goLog?.trimmingCharacters(in: .whitespacesAndNewlines), !goLog.isEmpty {
            try goLog.write(to: goLogURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: goLogURL(for: artifactURL))
        }

        if let nativeLog = contents.nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines), !nativeLog.isEmpty {
            try nativeLog.write(to: nativeLogURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: nativeLogURL(for: artifactURL))
        }

        if let configContent = contents.configContent?.trimmingCharacters(in: .whitespacesAndNewlines), !configContent.isEmpty {
            try configContent.write(to: configURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: configURL(for: artifactURL))
        }

        let metadataData = try metadataEncoder.encode(metadata)
        try metadataData.write(to: metadataURL(for: artifactURL), options: .atomic)
    }

    public static func readMetadata(for artifactURL: URL) -> CrashReportMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: artifactURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(CrashReportMetadata.self, from: data)
    }

    public static func readContents(for artifactURL: URL) -> CrashReportArtifactContents {
        let goLog = try? String(contentsOf: goLogURL(for: artifactURL), encoding: .utf8)
        let nativeLog = try? String(contentsOf: nativeLogURL(for: artifactURL), encoding: .utf8)
        let configContent = try? String(contentsOf: configURL(for: artifactURL), encoding: .utf8)
        return CrashReportArtifactContents(goLog: goLog, nativeLog: nativeLog, configContent: configContent)
    }

    static func removeArtifact(at artifactURL: URL) {
        ReportArchive.removeArtifact(at: artifactURL)
    }

    static func crashDate(for artifactURL: URL) -> Date? {
        ReportArchive.parseArtifactDate(for: artifactURL)
    }

    static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    static func displayContent(for contents: CrashReportArtifactContents) -> String {
        let goBody = contents.goLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nativeBody = contents.nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if nativeBody.isEmpty {
            return goBody
        }
        if goBody.isEmpty {
            return nativeBody
        }

        var sections: [String] = []
        sections.append("===== Go Crash =====\n\n" + goBody)
        sections.append("===== Native Crash =====\n\n" + nativeBody)
        return sections.joined(separator: "\n\n")
    }

    private static func nextAvailableArtifactURL(for date: Date) -> URL {
        ReportArchive.nextAvailableArtifactURL(in: crashReportsDirectory, for: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return encoder
    }()
}
