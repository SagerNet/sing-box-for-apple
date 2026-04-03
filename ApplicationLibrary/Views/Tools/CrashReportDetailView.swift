import Library
import SwiftUI

@MainActor
public struct CrashReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var alert: AlertState?
    @State private var files: [CrashReportFile] = []
    @State private var isLoading = true

    #if os(macOS)
        @State private var sharePresented = false
        @State private var shareItemURL: URL?
    #elseif os(tvOS)
        @State private var showExport = false
    #endif

    let report: CrashReport

    public init(report: CrashReport) {
        self.report = report
    }

    private var manager: CrashReportManager {
        environments.crashReportManager
    }

    #if !os(tvOS)
        private func shareReport(includeConfig: Bool) async {
            do {
                let zipURL = try await createReportZip(
                    reportID: report.id, fileURL: report.fileURL,
                    cacheSubdirectory: ReportType.crash.directoryName, includeConfig: includeConfig
                )
                #if os(iOS)
                    presentShareSheet(zipURL)
                #elseif os(macOS)
                    shareItemURL = zipURL
                    sharePresented = true
                #endif
            } catch {
                alert = AlertState(action: "export crash reports", error: error)
            }
        }
    #endif

    public var body: some View {
        FormView {
            if !isLoading, !files.isEmpty {
                Section("Files") {
                    ForEach(files) { file in
                        if file.id == .metadata {
                            FormNavigationLink {
                                MetadataFormView(url: file.fileURL, title: file.displayName)
                            } label: {
                                Text(file.displayName)
                            }
                        } else {
                            FormNavigationLink {
                                ReportFileContentView(fileURL: file.fileURL, displayName: file.displayName)
                            } label: {
                                Text(file.displayName)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if files.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task {
                files = await manager.availableFiles(for: report)
                manager.markAsRead(report)
                isLoading = false
            }
        }
        .alert($alert)
        #if os(tvOS)
            .navigationDestination(isPresented: $showExport) {
                ExportReportView(reportType: .crash, reportURL: report.fileURL, reportDate: report.date)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
        #elseif os(macOS)
            .background(SharingServicePicker($sharePresented, $alert, $shareItemURL))
        #endif
            .toolbar {
                if !isLoading, !files.isEmpty {
                    #if os(tvOS)
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                showExport = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                Task {
                                    await manager.delete(report)
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                            }
                            .tint(.red)
                        }
                    #else
                        if files.contains(where: { $0.id == .configContent }) {
                            Menu {
                                Button {
                                    Task {
                                        await shareReport(includeConfig: false)
                                    }
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    Task {
                                        await shareReport(includeConfig: true)
                                    }
                                } label: {
                                    Label("Share With Configuration", systemImage: "square.and.arrow.up.on.square")
                                }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                Task {
                                    await shareReport(includeConfig: false)
                                }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await manager.delete(report)
                                dismiss()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                                .foregroundStyle(.red)
                        }
                        .tint(.red)
                    #endif
                }
            }
            .navigationTitle(report.date.formatted(date: .abbreviated, time: .shortened))
    }
}
