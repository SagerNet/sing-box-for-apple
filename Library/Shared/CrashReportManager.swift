import CrashReporter
import Foundation
import Libbox
import os
import SwiftUI

private let logger = Logger(category: "CrashReportManager")

public struct CrashReport: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let fileURL: URL
    public var isRead: Bool
    public let origin: String?
}

public struct CrashReportFile: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case goLog
        case nativeLog
        case metadata
        case configContent
    }

    public let id: Kind
    public let displayName: String
    public let fileURL: URL
}

@MainActor
public class CrashReportManager: ObservableObject {
    @Published public private(set) var reports: [CrashReport] = []
    @Published public private(set) var unreadCount: Int = 0

    public init() {}

    public nonisolated func refresh() async {
        let reports = await BlockingIO.run {
            Self.archivePendingCrashLogs()
            Self.importPendingNativeCrashReports()
            Self.coalesceArchivedCrashReports()
            return Self.scanCrashReports()
        }
        await MainActor.run {
            self.reports = reports
            self.unreadCount = reports.filter { !$0.isRead }.count
        }
    }

    private nonisolated static func archivePendingCrashLogs() {
        for source in ["NetworkExtension", "Application"] {
            let url = FilePath.workingDirectory.appendingPathComponent("CrashReport-\(source).log")
            let oldURL = FilePath.workingDirectory.appendingPathComponent("CrashReport-\(source).log.old")
            archivePendingGoCrashLog(url, source: source)
            archivePendingGoCrashLog(oldURL, source: source)
        }

        #if os(macOS)
            if Variant.useSystemExtension {
                collectAndArchiveCrashArtifactsViaHelper()
            }
        #endif
    }

    #if os(macOS)
        private nonisolated static func collectAndArchiveCrashArtifactsViaHelper() {
            guard HelperServiceManager.rootHelperStatus == .enabled else {
                logger.debug("collectAndArchiveCrashArtifactsViaHelper: root helper not enabled, skipping")
                return
            }

            let artifacts: CrashArtifactsResult
            do {
                artifacts = try RootHelperClient.shared.collectAllCrashArtifacts()
            } catch {
                logger.warning("collectAndArchiveCrashArtifactsViaHelper: \(error.localizedDescription)")
                return
            }

            var configContent: String?
            for crashLog in artifacts.crashLogs {
                if crashLog.fileName == ReportArchive.configFileName {
                    let trimmed = crashLog.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        configContent = crashLog.content
                    }
                    continue
                }

                guard !crashLog.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                let metadata: CrashReportMetadata
                if crashLog.fileName.contains("RootHelper") {
                    metadata = CrashReportMetadataBuilder.normalized(
                        CrashReportMetadataBuilder.rootHelperGoMetadata(crashDate: crashLog.modificationDate),
                        content: crashLog.content
                    )
                } else {
                    metadata = CrashReportMetadataBuilder.normalized(
                        CrashReportMetadataBuilder.systemExtensionGoMetadata(crashDate: crashLog.modificationDate),
                        content: crashLog.content
                    )
                }

                _ = try? CrashReportArchive.writeArchivedReport(
                    contents: CrashReportArtifactContents(goLog: crashLog.content, configContent: configContent),
                    date: crashLog.modificationDate,
                    metadata: metadata
                )
            }

            for (data, source) in [
                (artifacts.extensionNativeCrashData, "NetworkExtension"),
                (artifacts.helperNativeCrashData, "RootHelper"),
            ] {
                guard let data, !data.isEmpty else {
                    continue
                }
                do {
                    let crashReport = try PLCrashReport(data: data)
                    guard let text = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS),
                          !text.isEmpty
                    else {
                        continue
                    }
                    let crashDate = crashReport.systemInfo.timestamp ?? Date()
                    let metadata = CrashReportMetadataBuilder.nativeMetadata(for: crashReport, content: text, source: source)
                    _ = try CrashReportArchive.writeArchivedReport(
                        contents: CrashReportArtifactContents(nativeLog: text),
                        date: crashDate,
                        metadata: metadata
                    )
                } catch {
                    continue
                }
            }
        }
    #endif

    private nonisolated static func archivePendingGoCrashLog(_ url: URL, source: String) {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else { return }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let crashDate = (attrs?[.modificationDate] as? Date) ?? Date()
        let metadata = CrashReportMetadataBuilder.normalized(
            CrashReportMetadataBuilder.goMetadata(source: source, crashDate: crashDate),
            content: content
        )

        let configContent = readAndCleanConfigSnapshot()

        do {
            _ = try CrashReportArchive.writeArchivedReport(
                contents: CrashReportArtifactContents(goLog: content, configContent: configContent),
                date: crashDate,
                metadata: metadata
            )
            try? FileManager.default.removeItem(at: url)
        } catch {
            return
        }
    }

    private nonisolated static func readAndCleanConfigSnapshot() -> String? {
        let url = FilePath.workingDirectory.appendingPathComponent(ReportArchive.configFileName)
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return content
    }

    private nonisolated static func scanCrashReports() -> [CrashReport] {
        let dir = CrashReportArchive.crashReportsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            .compactMap { url -> CrashReport? in
                let date = CrashReportArchive.crashDate(for: url)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date.distantPast
                let origin = CrashReportArchive.readMetadata(for: url)?.deviceOrigin
                return CrashReport(
                    id: url.lastPathComponent,
                    date: date,
                    fileURL: url,
                    isRead: FileManager.default.fileExists(atPath: url.appendingPathComponent(ReportArchive.readMarkerFileName).path),
                    origin: origin
                )
            }
            .sorted { $0.date > $1.date }
    }

    private nonisolated static func importPendingNativeCrashReports() {
        var pendingReports: [(bundleIdentifier: String, source: String)] = []
        for bundleIdentifier in AppConfiguration.packetTunnelBundleIDs {
            pendingReports.append((bundleIdentifier, "NetworkExtension"))
        }
        if let appBundleIdentifier = Bundle.main.bundleIdentifier {
            pendingReports.append((appBundleIdentifier, "Application"))
        }
        for (bundleIdentifier, source) in pendingReports {
            let reportURL = CrashReportArchive.pendingNativeCrashReportURL(bundleIdentifier: bundleIdentifier)
            guard let data = try? Data(contentsOf: reportURL), !data.isEmpty else {
                continue
            }

            do {
                let crashReport = try PLCrashReport(data: data)
                guard let text = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS),
                      !text.isEmpty
                else {
                    continue
                }

                let attrs = try? FileManager.default.attributesOfItem(atPath: reportURL.path)
                let crashDate = crashReport.systemInfo.timestamp
                    ?? (attrs?[.modificationDate] as? Date)
                    ?? Date()
                let metadata = CrashReportMetadataBuilder.nativeMetadata(for: crashReport, content: text, source: source)
                let configContent = readAndCleanConfigSnapshot()
                _ = try CrashReportArchive.writeArchivedReport(
                    contents: CrashReportArtifactContents(nativeLog: text, configContent: configContent),
                    date: crashDate,
                    metadata: metadata
                )
                try? FileManager.default.removeItem(at: reportURL)
            } catch {
                continue
            }
        }
    }

    private nonisolated static func coalesceArchivedCrashReports() {
        let records = loadArchivedReportRecords()
        let goOnlyRecords = records.filter { $0.contents.goLog != nil && $0.contents.nativeLog == nil }
        let nativeOnlyRecords = records.filter { $0.contents.nativeLog != nil && $0.contents.goLog == nil }
        guard !goOnlyRecords.isEmpty, !nativeOnlyRecords.isEmpty else {
            return
        }

        var usedGoReportURLs: Set<URL> = []
        for nativeRecord in nativeOnlyRecords {
            guard let goRecord = matchingGoReport(for: nativeRecord, among: goOnlyRecords, excluding: usedGoReportURLs) else {
                continue
            }

            let mergedMetadata = CrashReportMetadataBuilder.mergedMetadata(
                go: goRecord.metadata,
                goContent: goRecord.contents.goLog ?? "",
                native: nativeRecord.metadata,
                nativeContent: nativeRecord.contents.nativeLog ?? ""
            )
            let mergedContents = CrashReportArtifactContents(
                goLog: goRecord.contents.goLog,
                nativeLog: nativeRecord.contents.nativeLog,
                configContent: goRecord.contents.configContent ?? nativeRecord.contents.configContent
            )

            do {
                try CrashReportArchive.rewriteArchivedReport(
                    at: goRecord.reportURL,
                    contents: mergedContents,
                    metadata: mergedMetadata
                )
                CrashReportArchive.removeArtifact(at: nativeRecord.reportURL)
                usedGoReportURLs.insert(goRecord.reportURL)
            } catch {
                continue
            }
        }
    }

    public nonisolated func availableFiles(for report: CrashReport) async -> [CrashReportFile] {
        await BlockingIO.run {
            let fm = FileManager.default
            var files: [CrashReportFile] = []
            let metadataURL = CrashReportArchive.metadataURL(for: report.fileURL)
            if fm.fileExists(atPath: metadataURL.path) {
                files.append(CrashReportFile(id: .metadata, displayName: "Metadata", fileURL: metadataURL))
            }
            let nativeURL = CrashReportArchive.nativeLogURL(for: report.fileURL)
            if fm.fileExists(atPath: nativeURL.path) {
                files.append(CrashReportFile(id: .nativeLog, displayName: "Crash Report", fileURL: nativeURL))
            }
            let goURL = CrashReportArchive.goLogURL(for: report.fileURL)
            if fm.fileExists(atPath: goURL.path) {
                files.append(CrashReportFile(id: .goLog, displayName: "Go Crash Log", fileURL: goURL))
            }
            let configURL = CrashReportArchive.configURL(for: report.fileURL)
            if fm.fileExists(atPath: configURL.path) {
                files.append(CrashReportFile(id: .configContent, displayName: "Configuration", fileURL: configURL))
            }
            return files
        }
    }

    public func markAsRead(_ report: CrashReport) {
        FileManager.default.createFile(atPath: report.fileURL.appendingPathComponent(ReportArchive.readMarkerFileName).path, contents: nil)
        if let idx = reports.firstIndex(where: { $0.id == report.id }), !reports[idx].isRead {
            reports[idx].isRead = true
            unreadCount = max(0, unreadCount - 1)
        }
    }

    public nonisolated func delete(_ report: CrashReport) async {
        await BlockingIO.run {
            CrashReportArchive.removeArtifact(at: report.fileURL)
        }
        await MainActor.run {
            let wasUnread = reports.first { $0.id == report.id }.map { !$0.isRead } ?? false
            reports.removeAll { $0.id == report.id }
            if wasUnread {
                unreadCount = max(0, unreadCount - 1)
            }
        }
    }

    public nonisolated func deleteAll() async {
        let dir = CrashReportArchive.crashReportsDirectory
        await BlockingIO.run {
            try? FileManager.default.removeItem(at: dir)
        }
        await MainActor.run {
            reports.removeAll()
            unreadCount = 0
        }
    }

    private nonisolated static func loadArchivedReportRecords() -> [ArchivedCrashReportRecord] {
        let dir = CrashReportArchive.crashReportsDirectory
        guard let reportURLs = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return reportURLs
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            .compactMap { reportURL in
                let contents = CrashReportArchive.readContents(for: reportURL)
                guard let metadata = CrashReportArchive.readMetadata(for: reportURL),
                      !contents.isEmpty
                else {
                    return nil
                }
                let date = CrashReportArchive.crashDate(for: reportURL)
                    ?? (try? reportURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date.distantPast
                return ArchivedCrashReportRecord(
                    reportURL: reportURL,
                    date: date,
                    contents: contents,
                    metadata: metadata
                )
            }
    }

    private nonisolated static func matchingGoReport(
        for nativeRecord: ArchivedCrashReportRecord,
        among goRecords: [ArchivedCrashReportRecord],
        excluding excludedReportURLs: Set<URL>
    ) -> ArchivedCrashReportRecord? {
        goRecords
            .filter { !excludedReportURLs.contains($0.reportURL) }
            .filter { canMerge($0, nativeRecord) }
            .min { lhs, rhs in
                abs(lhs.date.timeIntervalSince(nativeRecord.date)) < abs(rhs.date.timeIntervalSince(nativeRecord.date))
            }
    }

    private nonisolated static func canMerge(_ goRecord: ArchivedCrashReportRecord, _ nativeRecord: ArchivedCrashReportRecord) -> Bool {
        if let goSource = goRecord.metadata.source,
           let nativeSource = nativeRecord.metadata.source,
           goSource != nativeSource
        {
            return false
        }

        if let goBundleIdentifier = goRecord.metadata.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !goBundleIdentifier.isEmpty,
           let nativeBundleIdentifier = nativeRecord.metadata.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nativeBundleIdentifier.isEmpty,
           goBundleIdentifier != nativeBundleIdentifier
        {
            return false
        }

        return abs(goRecord.date.timeIntervalSince(nativeRecord.date)) <= 10
    }
}

private struct ArchivedCrashReportRecord {
    let reportURL: URL
    let date: Date
    let contents: CrashReportArtifactContents
    let metadata: CrashReportMetadata
}

enum CrashReportMetadataBuilder {
    static func goMetadata(source: String, crashDate: Date) -> CrashReportMetadata {
        CrashReportMetadata(
            source: source,
            crashedAt: CrashReportArchive.iso8601String(from: crashDate)
        )
    }

    #if os(macOS)
        static func systemExtensionGoMetadata(crashDate: Date) -> CrashReportMetadata {
            CrashReportMetadata(
                source: "NetworkExtension",
                bundleIdentifier: AppConfiguration.systemExtensionBundleID,
                crashedAt: CrashReportArchive.iso8601String(from: crashDate)
            )
        }

        static func rootHelperGoMetadata(crashDate: Date) -> CrashReportMetadata {
            CrashReportMetadata(
                source: "RootHelper",
                bundleIdentifier: AppConfiguration.rootHelperBundleID,
                crashedAt: CrashReportArchive.iso8601String(from: crashDate)
            )
        }
    #endif

    static func mergedMetadata(
        go: CrashReportMetadata,
        goContent: String,
        native: CrashReportMetadata,
        nativeContent: String
    ) -> CrashReportMetadata {
        normalized(
            CrashReportMetadata(
                source: firstNonEmpty(native.source, go.source),
                bundleIdentifier: firstNonEmpty(native.bundleIdentifier, go.bundleIdentifier),
                processName: firstNonEmpty(native.processName, go.processName),
                processPath: firstNonEmpty(native.processPath, go.processPath),
                startedAt: firstNonEmpty(native.startedAt, go.startedAt),
                appVersion: firstNonEmpty(go.appVersion, native.appVersion),
                appMarketingVersion: firstNonEmpty(go.appMarketingVersion, native.appMarketingVersion),
                coreVersion: firstNonEmpty(go.coreVersion, native.coreVersion),
                goVersion: firstNonEmpty(go.goVersion, native.goVersion),
                crashedAt: earliestTimestamp(go.crashedAt, native.crashedAt),
                signalName: firstNonEmpty(native.signalName, go.signalName),
                signalCode: firstNonEmpty(native.signalCode, go.signalCode),
                exceptionName: firstNonEmpty(go.exceptionName, native.exceptionName),
                exceptionReason: firstNonEmpty(go.exceptionReason, native.exceptionReason)
            ),
            content: CrashReportArchive.displayContent(for: CrashReportArtifactContents(goLog: goContent, nativeLog: nativeContent))
        )
    }

    static func nativeMetadata(for crashReport: PLCrashReport, content: String, source: String) -> CrashReportMetadata {
        let processInfo = crashReport.hasProcessInfo ? crashReport.processInfo : nil
        return normalized(
            CrashReportMetadata(
                source: source,
                bundleIdentifier: crashReport.applicationInfo.applicationIdentifier,
                processName: processInfo?.processName,
                processPath: processInfo?.processPath,
                startedAt: processInfo?.processStartTime.map(CrashReportArchive.iso8601String(from:)),
                appVersion: crashReport.applicationInfo.applicationVersion,
                appMarketingVersion: crashReport.applicationInfo.applicationMarketingVersion,
                crashedAt: crashReport.systemInfo.timestamp.map(CrashReportArchive.iso8601String(from:)),
                signalName: crashReport.signalInfo.name,
                signalCode: crashReport.signalInfo.code,
                exceptionName: crashReport.hasExceptionInfo ? crashReport.exceptionInfo.exceptionName : nil,
                exceptionReason: crashReport.hasExceptionInfo ? crashReport.exceptionInfo.exceptionReason : nil
            ),
            content: content
        )
    }

    static func normalized(_ metadata: CrashReportMetadata, content: String? = nil) -> CrashReportMetadata {
        let bundleIdentifier = normalizedString(metadata.bundleIdentifier)
        let processBundle = bundleIdentifier.flatMap(bundle(for:))
        let processPath = firstNonEmpty(
            metadata.processPath,
            normalizedString(processBundle?.executableURL?.path)
        )
        let executableNameFromPath = processPath.flatMap {
            normalizedString(URL(fileURLWithPath: $0).lastPathComponent)
        }
        let appBundle = containingAppBundle(for: processBundle) ?? currentAppBundle()
        let parsedDetails = parseCrashDetails(from: content)

        return CrashReportMetadata(
            source: metadata.source,
            bundleIdentifier: bundleIdentifier,
            processName: firstNonEmpty(
                metadata.processName,
                normalizedString(processBundle?.executableURL?.lastPathComponent),
                executableNameFromPath,
                bundleIdentifier
            ),
            processPath: processPath,
            startedAt: normalizedString(metadata.startedAt),
            appVersion: firstNonEmpty(bundleBuildVersion(appBundle), metadata.appVersion),
            appMarketingVersion: firstNonEmpty(bundleMarketingVersion(appBundle), metadata.appMarketingVersion),
            coreVersion: firstNonEmpty(metadata.coreVersion, normalizedString(LibboxVersion())),
            goVersion: firstNonEmpty(metadata.goVersion, normalizedString(LibboxGoVersion())),
            crashedAt: normalizedString(metadata.crashedAt),
            signalName: firstNonEmpty(metadata.signalName, parsedDetails.signalName),
            signalCode: firstNonEmpty(metadata.signalCode, parsedDetails.signalCode),
            exceptionName: firstNonEmpty(metadata.exceptionName, parsedDetails.exceptionName),
            exceptionReason: firstNonEmpty(metadata.exceptionReason, parsedDetails.exceptionReason)
        )
    }

    private static func bundle(for bundleIdentifier: String) -> Bundle? {
        if Bundle.main.bundleIdentifier == bundleIdentifier {
            return Bundle.main
        }
        return discoveredBundles[bundleIdentifier]
    }

    private static func currentAppBundle() -> Bundle {
        containingAppBundle(for: Bundle.main) ?? Bundle.main
    }

    private static func containingAppBundle(for bundle: Bundle?) -> Bundle? {
        guard let bundle else {
            return nil
        }

        var currentURL = bundle.bundleURL
        while currentURL.path != "/" {
            if currentURL.pathExtension.lowercased() == "app" {
                return Bundle(url: currentURL)
            }
            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL == currentURL {
                break
            }
            currentURL = parentURL
        }

        return nil
    }

    private static func bundleBuildVersion(_ bundle: Bundle?) -> String? {
        normalizedString(bundle?.infoDictionary?["CFBundleVersion"] as? String)
    }

    private static func bundleMarketingVersion(_ bundle: Bundle?) -> String? {
        normalizedString(bundle?.infoDictionary?["CFBundleShortVersionString"] as? String)
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "unknown"
        else {
            return nil
        }
        return trimmed
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value = normalizedString(value) {
                return value
            }
        }
        return nil
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static func earliestTimestamp(_ values: String?...) -> String? {
        let timestamps = values.compactMap { value -> (String, Date)? in
            guard let value = normalizedString(value),
                  let date = iso8601Formatter.date(from: value)
            else {
                return nil
            }
            return (value, date)
        }
        if let earliest = timestamps.min(by: { $0.1 < $1.1 }) {
            return earliest.0
        }
        for value in values {
            if let value = normalizedString(value) {
                return value
            }
        }
        return nil
    }

    private static let discoveredBundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]

        func addBundle(_ bundle: Bundle?) {
            guard let bundle,
                  let bundleIdentifier = bundle.bundleIdentifier
            else {
                return
            }
            bundles[bundleIdentifier] = bundle
        }

        let appBundle = currentAppBundle()
        addBundle(appBundle)
        addBundle(Bundle.main)

        guard let enumerator = FileManager.default.enumerator(
            at: appBundle.bundleURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return bundles
        }

        let bundleExtensions: Set = ["app", "appex", "systemextension"]
        for case let url as URL in enumerator {
            let pathExtension = url.pathExtension.lowercased()
            guard bundleExtensions.contains(pathExtension) else {
                continue
            }
            addBundle(Bundle(url: url))
            enumerator.skipDescendants()
        }

        return bundles
    }()

    private struct ParsedCrashDetails {
        var signalName: String?
        var signalCode: String?
        var exceptionName: String?
        var exceptionReason: String?
    }

    private static func parseCrashDetails(from content: String?) -> ParsedCrashDetails {
        guard let content else {
            return ParsedCrashDetails()
        }

        var details = ParsedCrashDetails()
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if details.exceptionReason == nil {
                if line.hasPrefix("panic: ") {
                    details.exceptionName = "panic"
                    details.exceptionReason = normalizedString(String(line.dropFirst("panic: ".count)))
                } else if line.hasPrefix("fatal error: ") {
                    details.exceptionName = "fatal error"
                    details.exceptionReason = normalizedString(String(line.dropFirst("fatal error: ".count)))
                }
            }

            if details.signalName == nil,
               let parsedSignal = parseSignal(from: line)
            {
                details.signalName = parsedSignal.name
                details.signalCode = parsedSignal.code
            }

            if details.exceptionReason != nil,
               details.signalName != nil
            {
                break
            }
        }

        return details
    }

    private static func parseSignal(from line: String) -> (name: String?, code: String?)? {
        let signalSection: Substring
        if let range = line.range(of: "[signal ") {
            signalSection = line[range.upperBound...]
        } else if line.hasPrefix("signal ") {
            signalSection = line.dropFirst("signal ".count)
        } else {
            return nil
        }

        let signalName = normalizedString(
            String(signalSection.prefix { character in
                character != ":" && character != "]" && !character.isWhitespace
            })
        )
        guard signalName != nil else {
            return nil
        }

        var signalCode: String?
        if let codeRange = signalSection.range(of: " code=") {
            let codeSection = signalSection[codeRange.upperBound...]
            signalCode = normalizedString(
                String(codeSection.prefix { character in
                    character != "]" && !character.isWhitespace
                })
            )
        }

        return (signalName, signalCode)
    }
}
