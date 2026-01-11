import Libbox
import Library
import SwiftUI
#if os(iOS)
    import FileProvider
    import UIKit
#elseif os(macOS)
    import ServiceManagement
#endif

@MainActor
public struct CoreView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var alert: AlertState?

    @State private var disableDeprecatedWarnings = false

    @State private var version = ""
    @State private var dataSize: String?

    #if os(macOS)
        @State private var helperUnavailable = false
    #endif

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
                    if let dataSize {
                        FormTextItem("Data Size", dataSize)
                    } else {
                        #if os(macOS)
                            HStack {
                                Text("Data Size")
                                Spacer()
                                Text("Unavailable")
                                    .foregroundStyle(.red)
                                    .onTapGesture {
                                        alert = helperRequiredAlert()
                                    }
                            }
                        #endif
                    }

                    if Variant.isBeta {
                        Section {}
                        FormToggle("Disable Deprecated Warnings", "Do not show warnings about usages of deprecated features.", $disableDeprecatedWarnings) { newValue in
                            await SharedPreferences.disableDeprecatedWarnings.set(newValue)
                        }
                    }

                    Section("Working Directory") {
                        #if os(macOS)
                            if !Variant.useSystemExtension {
                                FormButton {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FilePath.workingDirectory.relativePath)
                                } label: {
                                    Label("Open", systemImage: "macwindow.and.cursorarrow")
                                }
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
        .onAppear {
            guard !isLoading else {
                return
            }
            Task {
                await refreshWorkingDirectorySize()
            }
        }
        .onChangeCompat(of: scenePhase) { newValue in
            guard newValue == .active, !isLoading else {
                return
            }
            Task {
                await refreshWorkingDirectorySize()
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private nonisolated func loadSettings() async {
        if Variant.screenshotMode {
            await MainActor.run {
                version = "<redacted>"
                dataSize = LibboxFormatBytes(1000 * 1000 * 10)
                isLoading = false
            }
        } else {
            await MainActor.run {
                version = LibboxVersion()
                #if os(macOS)
                    if Variant.useSystemExtension {
                        helperUnavailable = HelperServiceManager.rootHelperStatus != .enabled
                    }
                #endif
                isLoading = false
            }
            await loadSettingsBackground()
        }
    }

    private nonisolated func loadSettingsBackground() async {
        let disableDeprecatedWarnings = await SharedPreferences.disableDeprecatedWarnings.get()
        await MainActor.run {
            self.disableDeprecatedWarnings = disableDeprecatedWarnings
        }
        await refreshWorkingDirectorySize()
    }

    private nonisolated func refreshWorkingDirectorySize() async {
        guard !Variant.screenshotMode else {
            return
        }
        #if os(macOS)
            let helperUnavailable = Variant.useSystemExtension && HelperServiceManager.rootHelperStatus != .enabled
        #endif
        let dataSize: String?
        #if os(macOS)
            if Variant.useSystemExtension {
                if helperUnavailable {
                    dataSize = nil
                } else if let size = try? RootHelperClient.shared.getWorkingDirectorySize() {
                    dataSize = LibboxFormatBytes(size)
                } else {
                    dataSize = nil
                }
            } else {
                dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
            }
        #else
            dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
        #endif
        await MainActor.run {
            #if os(macOS)
                self.helperUnavailable = helperUnavailable
            #endif
            self.dataSize = dataSize
        }
    }

    private func confirmDestroyWorkingDirectory() async {
        #if os(macOS)
            if helperUnavailable {
                alert = helperRequiredAlert()
                return
            }
        #endif
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
        do {
            try await environments.extensionProfile!.stop()
            await destroyWorkingDirectory()
        } catch {
            alert = AlertState(error: error)
        }
    }

    private func destroyWorkingDirectory() async {
        do {
            #if os(macOS)
                if Variant.useSystemExtension {
                    try RootHelperClient.shared.cleanWorkingDirectory()
                } else {
                    try clearWorkingDirectoryContents()
                }
            #else
                try clearWorkingDirectoryContents()
                #if os(iOS)
                    if #available(iOS 16.0, *) {
                        await notifyFileProviderWorkingDirectoryChanged()
                    }
                #endif
            #endif
            isLoading = true
        } catch {
            alert = AlertState(error: error)
        }
    }

    private func clearWorkingDirectoryContents() throws {
        let url = FilePath.workingDirectory
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    #if os(macOS)
        private func helperRequiredAlert() -> AlertState {
            AlertState(
                title: String(localized: "Helper Service Required"),
                message: String(localized: "Managing working directory requires Helper Service."),
                primaryButton: .default(String(localized: "App Settings")) {
                    NotificationCenter.default.post(name: .navigateToSettingsPage, object: SettingsPage.app)
                },
                secondaryButton: .cancel(String(localized: "Ok"))
            )
        }
    #endif

    #if os(iOS)
        @available(iOS 16.0, *)
        private nonisolated func fileProviderManager() async throws -> NSFileProviderManager {
            let domains = try await NSFileProviderManager.domains()
            guard let domain = domains.first(where: { $0.identifier.rawValue == AppConfiguration.fileProviderDomainID }) else {
                throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "File provider domain not found"])
            }
            guard let manager = NSFileProviderManager(for: domain) else {
                throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get file provider manager"])
            }
            return manager
        }

        @available(iOS 16.0, *)
        private nonisolated func notifyFileProviderWorkingDirectoryChanged() async {
            do {
                let manager = try await fileProviderManager()
                try await manager.signalEnumerator(for: .rootContainer)
                try await manager.signalEnumerator(for: .workingSet)
            } catch {
                await MainActor.run {
                    alert = AlertState(error: error)
                }
            }
        }

        @available(iOS 16.0, *)
        private nonisolated func openInFilesApp() async {
            do {
                let manager = try await fileProviderManager()
                try await manager.signalEnumerator(for: .workingSet)
                let url = try await manager.getUserVisibleURL(for: .rootContainer)
                guard let sharedURL = URL(string: "shareddocuments://\(url.path)") else {
                    throw NSError(domain: "CoreView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create shared documents URL"])
                }
                await MainActor.run {
                    UIApplication.shared.open(sharedURL)
                }
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
