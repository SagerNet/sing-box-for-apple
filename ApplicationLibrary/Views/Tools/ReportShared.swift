import Libbox
import Library
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct ReportLabel: View {
    let date: Date
    let isRead: Bool
    let origin: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRead ? .clear : .blue)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime)
                    .fontWeight(isRead ? .regular : .semibold)
                HStack(spacing: 4) {
                    Image(systemName: origin == ReportArchive.tvOSDeviceOrigin ? "appletv.fill" : Self.localDeviceIcon)
                    Text(origin == ReportArchive.tvOSDeviceOrigin ? "Apple TV" : "Local")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    #if os(iOS)
        private static let localDeviceIcon = "iphone"
    #elseif os(macOS)
        private static let localDeviceIcon = "desktopcomputer"
    #elseif os(tvOS)
        private static let localDeviceIcon = "appletv.fill"
    #endif
}

@MainActor
struct ReportFileContentView: View {
    @State private var content = ""
    @State private var isLoading = true

    let fileURL: URL
    let displayName: String

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .onAppear {
                        Task {
                            content = await Self.loadContent(fileURL: fileURL)
                            isLoading = false
                        }
                    }
            } else if content.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                    ScrollView {
                        PlainTextView(content: content)
                    }
                #else
                    PlainTextView(content: content)
                #endif
            }
        }
        .navigationTitle(displayName)
    }

    private nonisolated static func loadContent(fileURL: URL) async -> String {
        await BlockingIO.run {
            guard let data = try? Data(contentsOf: fileURL) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}

#if !os(tvOS)
    @MainActor
    func createReportZip(reportID: String, fileURL: URL, cacheSubdirectory: String, includeConfig: Bool) async throws -> URL {
        try await BlockingIO.run {
            let tempDir = FilePath.cacheDirectory.appendingPathComponent(cacheSubdirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("\(reportID).zip")
            try? FileManager.default.removeItem(at: tempURL)
            let strippedURL = tempDir.appendingPathComponent(reportID, isDirectory: true)
            try? FileManager.default.removeItem(at: strippedURL)
            try FileManager.default.copyItem(at: fileURL, to: strippedURL)
            try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.readMarkerFileName))
            if !includeConfig {
                try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.configFileName))
            }
            var error: NSError?
            LibboxCreateZipArchive(strippedURL.path, tempURL.path, &error)
            try? FileManager.default.removeItem(at: strippedURL)
            if let error { throw error }
            return tempURL
        }
    }

    #if os(iOS)
        @MainActor
        func presentShareSheet(_ item: URL) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.keyWindow?.rootViewController
            else {
                return
            }
            var topViewController = rootViewController
            while let presented = topViewController.presentedViewController {
                topViewController = presented
            }
            topViewController.present(
                UIActivityViewController(activityItems: [item], applicationActivities: nil),
                animated: true
            )
        }
    #endif
#endif
