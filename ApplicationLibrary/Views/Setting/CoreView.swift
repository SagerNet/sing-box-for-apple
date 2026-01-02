import Libbox
import Library
import SwiftUI
#if os(iOS)
    import FileProvider
    import UIKit
#endif

@MainActor
public struct CoreView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var alert: AlertState?

    @State private var disableDeprecatedWarnings = false

    @State private var version = ""
    @State private var dataSize = ""

    public init() {}
    public var body: some View {
        Group {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    FormTextItem("Version", version)
                    FormTextItem("Data Size", dataSize)

                    if Variant.isBeta {
                        Section {}
                        FormToggle("Disable Deprecated Warnings", "Do not show warnings about usages of deprecated features.", $disableDeprecatedWarnings) { newValue in
                            await SharedPreferences.disableDeprecatedWarnings.set(newValue)
                        }
                    }

                    Section("Working Directory") {
                        #if os(macOS)
                            FormButton {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FilePath.workingDirectory.relativePath)
                            } label: {
                                Label("Open", systemImage: "macwindow.and.cursorarrow")
                            }
                        #elseif os(iOS)
                            if #available(iOS 16.0, *) {
                                FormButton {
                                    Task {
                                        await openInFilesApp()
                                    }
                                } label: {
                                    Label("Browse", systemImage: "folder.fill")
                                }
                            }
                        #endif
                        FormButton(role: .destructive) {
                            Task {
                                await confirmDestroyWorkingDirectory()
                            }
                        } label: {
                            Label("Destroy", systemImage: "trash.fill")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Core")
        .alert($alert)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private nonisolated func loadSettings() async {
        if ApplicationLibrary.inPreview {
            await MainActor.run {
                version = "<redacted>"
                dataSize = LibboxFormatBytes(1000 * 1000 * 10)
                isLoading = false
            }
        } else {
            await MainActor.run {
                version = LibboxVersion()
                dataSize = "Loading..."
                isLoading = false
            }
            await loadSettingsBackground()
        }
    }

    private nonisolated func loadSettingsBackground() async {
        let disableDeprecatedWarnings = await SharedPreferences.disableDeprecatedWarnings.get()
        let dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
        await MainActor.run {
            self.disableDeprecatedWarnings = disableDeprecatedWarnings
            self.dataSize = dataSize
        }
    }

    private func confirmDestroyWorkingDirectory() async {
        if environments.extensionProfile?.status.isConnected == true {
            alert = AlertState(
                title: String(localized: "Service is Running"),
                message: String(localized: "The service must be stopped before destroying the working directory."),
                primaryButton: .destructive(String(localized: "Stop Service and Continue")) { [self] in
                    Task {
                        await stopServiceAndDestroy()
                    }
                },
                secondaryButton: .cancel()
            )
        } else {
            await destroyWorkingDirectory()
        }
    }

    private func stopServiceAndDestroy() async {
        try? await environments.extensionProfile?.stop()
        await destroyWorkingDirectory()
    }

    private nonisolated func destroyWorkingDirectory() async {
        try? FileManager.default.removeItem(at: FilePath.workingDirectory)
        await MainActor.run {
            isLoading = true
        }
    }

    #if os(iOS)
        @available(iOS 16.0, *)
        private nonisolated func openInFilesApp() async {
            do {
                let domains = try await NSFileProviderManager.domains()
                guard let domain = domains.first(where: { $0.identifier.rawValue == AppConfiguration.fileProviderDomainID }) else {
                    throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "File provider domain not found"])
                }
                guard let manager = NSFileProviderManager(for: domain) else {
                    throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get file provider manager"])
                }
                let url = try await manager.getUserVisibleURL(for: .rootContainer)
                guard let sharedURL = URL(string: "shareddocuments://\(url.path)") else {
                    throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create shared documents URL"])
                }
                await UIApplication.shared.open(sharedURL)
            } catch {
                await MainActor.run {
                    alert = AlertState(error: error)
                }
            }
        }
    #endif
}

private extension URL {
    func formattedSize() throws -> String? {
        guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else {
            return nil
        }
        let size = try urls.lazy.reduce(0) {
            try ($1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        guard let byteCount = formatter.string(for: size) else {
            return nil
        }
        return byteCount
    }
}
