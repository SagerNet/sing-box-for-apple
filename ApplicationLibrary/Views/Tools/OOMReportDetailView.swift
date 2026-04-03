import Library
import SwiftUI

@MainActor
public struct OOMReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var alert: AlertState?
    @State private var files: [OOMReportFile] = []
    @State private var isLoading = true

    #if os(macOS)
        @State private var sharePresented = false
        @State private var shareItemURL: URL?
    #elseif os(tvOS)
        @State private var showExport = false
    #endif

    let report: OOMReport

    public init(report: OOMReport) {
        self.report = report
    }

    private var manager: OOMReportManager {
        environments.oomReportManager
    }

    #if !os(tvOS)
        private func shareReport(includeConfig: Bool) async {
            do {
                let zipURL = try await createReportZip(
                    reportID: report.id, fileURL: report.fileURL,
                    cacheSubdirectory: ReportType.oom.directoryName, includeConfig: includeConfig
                )
                #if os(iOS)
                    presentShareSheet(zipURL)
                #elseif os(macOS)
                    shareItemURL = zipURL
                    sharePresented = true
                #endif
            } catch {
                alert = AlertState(action: "export OOM report", error: error)
            }
        }
    #endif

    public var body: some View {
        FormView {
            if !isLoading, !files.isEmpty {
                Section("Files") {
                    ForEach(files) { file in
                        if file.kind == .metadata {
                            FormNavigationLink {
                                MetadataFormView(url: file.fileURL, title: file.displayName)
                            } label: {
                                Text(file.displayName)
                            }
                        } else if file.kind == .configContent {
                            FormNavigationLink {
                                ReportFileContentView(fileURL: file.fileURL, displayName: file.displayName)
                            } label: {
                                Text(file.displayName)
                            }
                        } else {
                            Text(file.displayName)
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
                ExportReportView(reportType: .oom, reportURL: report.fileURL, reportDate: report.date)
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
                        if files.contains(where: { $0.kind == .configContent }) {
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
