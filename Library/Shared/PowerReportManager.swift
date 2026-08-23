import Foundation
import os
import SwiftUI

private let logger = Logger(category: "PowerReportManager")

public struct PowerReport: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let fileURL: URL
    public var isRead: Bool
    public let origin: String?
}

public struct PowerReportFile: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case metadata
        case configContent
        case timeline
        case events
        case goLog
        case profile
    }

    public let id: String
    public let kind: Kind
    public let displayName: String
    public let fileURL: URL
}

@MainActor
public class PowerReportManager: ObservableObject {
    @Published public private(set) var reports: [PowerReport] = []
    @Published public private(set) var unreadCount: Int = 0

    public init() {}

    public nonisolated func refresh() async {
        let reports = await BlockingIO.run {
            Self.scanReports()
        }
        await MainActor.run {
            self.reports = reports
            self.unreadCount = reports.filter { !$0.isRead }.count
        }
    }

    private nonisolated static func scanReports() -> [PowerReport] {
        let dir = PowerReportArchive.reportsDirectory
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
            .compactMap { url -> PowerReport? in
                let date = PowerReportArchive.reportDate(for: url)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date.distantPast
                let origin = PowerReportArchive.readMetadata(for: url)?.deviceOrigin
                return PowerReport(
                    id: url.lastPathComponent,
                    date: date,
                    fileURL: url,
                    isRead: FileManager.default.fileExists(atPath: url.appendingPathComponent(ReportArchive.readMarkerFileName).path),
                    origin: origin
                )
            }
            .sorted { $0.date > $1.date }
    }

    public nonisolated func availableFiles(for report: PowerReport) async -> [PowerReportFile] {
        await BlockingIO.run {
            let fm = FileManager.default
            var files: [PowerReportFile] = []

            let metadataURL = PowerReportArchive.metadataURL(for: report.fileURL)
            if fm.fileExists(atPath: metadataURL.path) {
                files.append(PowerReportFile(id: "metadata", kind: .metadata, displayName: "Metadata", fileURL: metadataURL))
            }

            let configURL = PowerReportArchive.configURL(for: report.fileURL)
            if fm.fileExists(atPath: configURL.path) {
                files.append(PowerReportFile(id: "config", kind: .configContent, displayName: "Configuration", fileURL: configURL))
            }

            let timelineURL = PowerReportArchive.timelineURL(for: report.fileURL)
            if fm.fileExists(atPath: timelineURL.path) {
                files.append(PowerReportFile(id: "timeline", kind: .timeline, displayName: timelineURL.lastPathComponent, fileURL: timelineURL))
            }

            let eventsURL = PowerReportArchive.eventsURL(for: report.fileURL)
            if fm.fileExists(atPath: eventsURL.path) {
                files.append(PowerReportFile(id: "events", kind: .events, displayName: eventsURL.lastPathComponent, fileURL: eventsURL))
            }

            let goLogURL = PowerReportArchive.goLogURL(for: report.fileURL)
            if fm.fileExists(atPath: goLogURL.path) {
                files.append(PowerReportFile(id: "log", kind: .goLog, displayName: "Log", fileURL: goLogURL))
            }

            for profileURL in PowerReportArchive.profileFiles(for: report.fileURL) {
                let name = profileURL.lastPathComponent
                files.append(PowerReportFile(id: name, kind: .profile, displayName: name, fileURL: profileURL))
            }

            return files
        }
    }

    public func markAsRead(_ report: PowerReport) {
        FileManager.default.createFile(atPath: report.fileURL.appendingPathComponent(ReportArchive.readMarkerFileName).path, contents: nil)
        if let idx = reports.firstIndex(where: { $0.id == report.id }), !reports[idx].isRead {
            reports[idx].isRead = true
            unreadCount = max(0, unreadCount - 1)
        }
    }

    public nonisolated func delete(_ report: PowerReport) async {
        await BlockingIO.run {
            PowerReportArchive.removeArtifact(at: report.fileURL)
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
        let dir = PowerReportArchive.reportsDirectory
        await BlockingIO.run {
            try? FileManager.default.removeItem(at: dir)
        }
        await MainActor.run {
            reports.removeAll()
            unreadCount = 0
        }
    }
}
