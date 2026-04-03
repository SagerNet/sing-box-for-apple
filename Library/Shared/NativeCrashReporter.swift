import CrashReporter
import Foundation
import os

public enum NativeCrashReporter {
    private static let logger = Logger(category: "NativeCrashReporter")
    private static let installLock = NSLock()
    private static var reporter: PLCrashReporter?

    public static func installForCurrentProcess(basePath: URL? = nil) {
        installLock.lock()
        defer {
            installLock.unlock()
        }

        guard reporter == nil else {
            return
        }

        let crashBasePath = basePath ?? CrashReportArchive.pendingNativeCrashBaseDirectory
        do {
            try FileManager.default.createDirectory(at: crashBasePath, withIntermediateDirectories: true)
            let config = PLCrashReporterConfig(
                signalHandlerType: .BSD,
                symbolicationStrategy: [],
                basePath: crashBasePath.path
            )
            guard let crashReporter = PLCrashReporter(configuration: config) else {
                logger.warning("Failed to create PLCrashReporter instance")
                return
            }
            try crashReporter.enableAndReturnError()
            reporter = crashReporter
        } catch {
            logger.warning("Failed to enable native crash reporting: \(error.localizedDescription)")
        }
    }

    public static func loadAndPurgePendingCrashReportData() -> Data? {
        installLock.lock()
        guard let reporter else {
            installLock.unlock()
            return nil
        }
        installLock.unlock()

        guard reporter.hasPendingCrashReport() else {
            return nil
        }

        let data = try? reporter.loadPendingCrashReportDataAndReturnError()
        reporter.purgePendingCrashReport()
        return data
    }

    public static func archiveLiveReportForCurrentProcess() {
        installLock.lock()
        guard let reporter else {
            installLock.unlock()
            return
        }
        installLock.unlock()

        do {
            let data = try reporter.generateLiveReportAndReturnError()
            let crashReport = try PLCrashReport(data: data)
            guard let text = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS),
                  !text.isEmpty
            else {
                return
            }
            let crashDate = crashReport.systemInfo.timestamp ?? Date()
            _ = try CrashReportArchive.writeArchivedReport(
                contents: CrashReportArtifactContents(nativeLog: text),
                date: crashDate,
                metadata: CrashReportMetadataBuilder.nativeMetadata(for: crashReport, content: text, source: "Application")
            )
        } catch {
            logger.warning("Failed to archive live native crash report: \(error.localizedDescription)")
        }
    }
}
