import Foundation
import os
import SwiftUI

private let logger = Logger(category: "OOMReportManager")

public struct OOMReport: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let fileURL: URL
    public var isRead: Bool
    public let origin: String?
}

public struct OOMReportFile: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case metadata
        case configContent
        case profile
    }

    public let id: String
    public let kind: Kind
    public let displayName: String
    public let fileURL: URL
}

@MainActor
public class OOMReportManager: ObservableObject {
    @Published public private(set) var reports: [OOMReport] = []
    @Published public private(set) var unreadCount: Int = 0

    public init() {}

    public nonisolated func refresh() async {
        let reports = await BlockingIO.run {
            #if os(macOS)
                if Variant.useSystemExtension {
                    Self.collectAndArchiveOOMReportsViaHelper()
                }
            #endif
            return Self.scanReports()
        }
        await MainActor.run {
            self.reports = reports
            self.unreadCount = reports.filter { !$0.isRead }.count
        }
    }

    private nonisolated static func scanReports() -> [OOMReport] {
        let dir = OOMReportArchive.reportsDirectory
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
            .compactMap { url -> OOMReport? in
                let date = OOMReportArchive.reportDate(for: url)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date.distantPast
                let origin = OOMReportArchive.readMetadata(for: url)?.deviceOrigin
                return OOMReport(
                    id: url.lastPathComponent,
                    date: date,
                    fileURL: url,
                    isRead: FileManager.default.fileExists(atPath: url.appendingPathComponent(ReportArchive.readMarkerFileName).path),
                    origin: origin
                )
            }
            .sorted { $0.date > $1.date }
    }

    public nonisolated func availableFiles(for report: OOMReport) async -> [OOMReportFile] {
        await BlockingIO.run {
            let fm = FileManager.default
            var files: [OOMReportFile] = []

            let metadataURL = OOMReportArchive.metadataURL(for: report.fileURL)
            if fm.fileExists(atPath: metadataURL.path) {
                files.append(OOMReportFile(id: "metadata", kind: .metadata, displayName: "Metadata", fileURL: metadataURL))
            }

            let configURL = OOMReportArchive.configURL(for: report.fileURL)
            if fm.fileExists(atPath: configURL.path) {
                files.append(OOMReportFile(id: "config", kind: .configContent, displayName: "Configuration", fileURL: configURL))
            }

            for profileURL in OOMReportArchive.profileFiles(for: report.fileURL) {
                let name = profileURL.lastPathComponent
                files.append(OOMReportFile(id: name, kind: .profile, displayName: name, fileURL: profileURL))
            }

            return files
        }
    }

    public func markAsRead(_ report: OOMReport) {
        FileManager.default.createFile(atPath: report.fileURL.appendingPathComponent(ReportArchive.readMarkerFileName).path, contents: nil)
        if let idx = reports.firstIndex(where: { $0.id == report.id }), !reports[idx].isRead {
            reports[idx].isRead = true
            unreadCount = max(0, unreadCount - 1)
        }
    }

    public nonisolated func delete(_ report: OOMReport) async {
        await BlockingIO.run {
            OOMReportArchive.removeArtifact(at: report.fileURL)
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
        let dir = OOMReportArchive.reportsDirectory
        await BlockingIO.run {
            try? FileManager.default.removeItem(at: dir)
        }
        await MainActor.run {
            reports.removeAll()
            unreadCount = 0
        }
    }

    #if os(macOS)
        private nonisolated static func collectAndArchiveOOMReportsViaHelper() {
            guard HelperServiceManager.rootHelperStatus == .enabled else {
                return
            }

            let artifacts: OOMReportArtifactsResult
            do {
                artifacts = try RootHelperClient.shared.collectOOMReportArtifacts()
            } catch {
                logger.warning("collectOOMReportArtifacts: \(error.localizedDescription)")
                return
            }

            let reportsDir = OOMReportArchive.reportsDirectory
            for report in artifacts.reports {
                let destURL = reportsDir.appendingPathComponent(report.directoryName, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
                    for file in report.files {
                        let fileURL = destURL.appendingPathComponent(file.name)
                        try file.data.write(to: fileURL, options: .atomic)
                    }
                } catch {
                    logger.warning("write OOM report \(report.directoryName): \(error.localizedDescription)")
                }
            }
        }
    #endif
}
