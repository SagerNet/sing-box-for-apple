import Libbox
import Library
import SwiftUI
import UniformTypeIdentifiers

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
    func createReportZip(reportID: String, fileURL: URL, cacheSubdirectory: String, includeConfig: Bool, includeLog: Bool, encrypt: Bool) async throws -> URL {
        try await BlockingIO.run {
            let tempDir = FilePath.cacheDirectory.appendingPathComponent(cacheSubdirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(encrypt ? "\(reportID).zip.age" : "\(reportID).zip")
            try? FileManager.default.removeItem(at: tempURL)
            let strippedURL = tempDir.appendingPathComponent(reportID, isDirectory: true)
            try? FileManager.default.removeItem(at: strippedURL)
            try FileManager.default.copyItem(at: fileURL, to: strippedURL)
            try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.readMarkerFileName))
            if !includeConfig {
                try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.configFileName))
            }
            if !includeLog {
                try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.goLogFileName))
                try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent(ReportArchive.nativeLogFileName))
            }
            var error: NSError?
            LibboxCreateZipArchive(strippedURL.path, tempURL.path, encrypt, &error)
            try? FileManager.default.removeItem(at: strippedURL)
            if let error { throw error }
            return tempURL
        }
    }

    enum ReportShareAction {
        case save
        case share
    }

    @MainActor
    struct ReportSharePopup: View {
        @Environment(\.dismiss) private var dismiss

        let hasConfig: Bool
        let hasLog: Bool
        @Binding var includeConfig: Bool
        @Binding var includeLog: Bool
        @Binding var useAgeEncryption: Bool
        let onSave: () -> Void
        let onShare: () -> Void

        var body: some View {
            NavigationSheet(title: "Share", size: .medium) {
                FormView {
                    if hasConfig || hasLog {
                        Section {
                            if hasLog {
                                Toggle("With Log", isOn: $includeLog)
                            }
                            if hasConfig {
                                Toggle("With Configuration", isOn: $includeConfig)
                            }
                        } footer: {
                            if hasLog {
                                Text("Logs and configuration files may contain private content and should not be made public.")
                            } else {
                                Text("Configuration files may contain private content and should not be made public.")
                            }
                        }
                    }
                    Section {
                        Toggle("Encrypt with age for Project S", isOn: $useAgeEncryption)
                    } footer: {
                        Text("[age](https://github.com/filosottile/age) is a modern and secure asymmetric encryption tool. When enabled, the zip file is encrypted with this project's public key so it can be posted publicly, e.g. in GitHub issues.")
                    }
                    Section {
                        FormButton {
                            onSave()
                            dismiss()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        FormButton {
                            onShare()
                            dismiss()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                #endif
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 240)
            #endif
        }
    }

    struct ReportZipDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            [.zip, .data]
        }

        private let url: URL

        init(url: URL) {
            self.url = url
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: tempURL)
            url = tempURL
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            try FileWrapper(url: url)
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
