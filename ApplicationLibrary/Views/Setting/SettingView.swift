import Foundation
import Libbox
import Library
import SwiftUI
#if os(macOS)
    import AppKit
    import ServiceManagement
#endif

@MainActor
public struct SettingView: View {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @State private var isLoading = true

    #if os(macOS)
        @State private var startAtLogin = false
        @Environment(\.showMenuBarExtra) private var showMenuBarExtra
        @State private var keepMenuBarInBackground = false
    #endif

    @State private var alwaysOn = false
    @State private var disableMemoryLimit = false

    #if !os(tvOS)
        @State private var includeAllNetworks = false
    #endif

    @State private var version = ""
    @State private var dataSize = ""
    @State private var taiwanFlagAvailable = false
    @State private var alert: Alert?

    public init() {}

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    #if os(macOS)
                        Section("MacOS") {
                            Toggle("Start At Login", isOn: $startAtLogin)
                                .onChangeCompat(of: startAtLogin) { newValue in
                                    Task {
                                        updateLoginItems(newValue)
                                    }
                                }
                            Toggle("Show in Menu Bar", isOn: showMenuBarExtra)
                                .onChange(of: showMenuBarExtra.wrappedValue) { newValue in
                                    Task {
                                        await SharedPreferences.showMenuBarExtra.set(newValue)
                                        if !newValue {
                                            keepMenuBarInBackground = false
                                        }
                                    }
                                }
                            if showMenuBarExtra.wrappedValue {
                                Toggle("Keep Menu Bar in Background", isOn: $keepMenuBarInBackground)
                                    .onChangeCompat(of: keepMenuBarInBackground) { newValue in
                                        Task {
                                            await SharedPreferences.menuBarExtraInBackground.set(newValue)
                                        }
                                    }
                            }
                        }
                    #endif
                    Section("Packet Tunnel") {
                        Toggle("Always On", isOn: $alwaysOn)
                            .onChangeCompat(of: alwaysOn) { newValue in
                                Task {
                                    await SharedPreferences.alwaysOn.set(newValue)
                                    await updateAlwaysOn(newValue)
                                }
                            }
                        Toggle("Disable Memory Limit", isOn: $disableMemoryLimit)
                            .onChangeCompat(of: disableMemoryLimit) { newValue in
                                Task {
                                    await SharedPreferences.disableMemoryLimit.set(newValue)
                                }
                            }
                        #if !os(tvOS)
                            Toggle("Include All Networks", isOn: $includeAllNetworks)
                                .onChangeCompat(of: includeAllNetworks) { newValue in
                                    Task {
                                        await SharedPreferences.includeAllNetworks.set(newValue)
                                    }
                                }
                        #endif
                        #if os(macOS)
                            if Variant.useSystemExtension {
                                HStack {
                                    Button("Update System Extension") {
                                        Task {
                                            do {
                                                if let result = try await SystemExtension.install(forceUpdate: true) {
                                                    switch result {
                                                    case .completed:
                                                        alert = Alert(
                                                            title: Text("Update"),
                                                            message: Text("System Extension updated."),
                                                            dismissButton: .default(Text("Ok")) {}
                                                        )
                                                    case .willCompleteAfterReboot:
                                                        alert = Alert(
                                                            title: Text("Update"),
                                                            message: Text("Reboot required."),
                                                            dismissButton: .default(Text("Ok")) {}
                                                        )
                                                    }
                                                }
                                            } catch {
                                                alert = Alert(error)
                                            }
                                        }
                                    }
                                    Button {
                                        Task {
                                            do {
                                                if let result = try await SystemExtension.uninstall() {
                                                    switch result {
                                                    case .completed:
                                                        alert = Alert(
                                                            title: Text("Uninstall"),
                                                            message: Text("System Extension removed."),
                                                            dismissButton: .default(Text("Ok")) {}
                                                        )
                                                    case .willCompleteAfterReboot:
                                                        alert = Alert(
                                                            title: Text("Uninstall"),
                                                            message: Text("Reboot required."),
                                                            dismissButton: .default(Text("Ok")) {}
                                                        )
                                                    }
                                                }
                                            } catch {
                                                alert = Alert(error)
                                            }
                                        }
                                    } label: {
                                        Text("Uninstall System Extension").foregroundColor(.red)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        #endif
                    }
                    Section("Core") {
                        FormTextItem("Version", version)
                        FormTextItem("Data Size", dataSize)
                        #if os(iOS) || os(tvOS)
                            NavigationLink(destination: ServiceLogView()) {
                                Text("View Service Log")
                            }
                            Button("Clear Working Directory") {
                                Task {
                                    await clearWorkingDirectory()
                                }
                            }
                            .foregroundColor(.red)
                        #elseif os(macOS)
                            HStack {
                                Button("View Service Log") {
                                    openWindow(id: ServiceLogView.windowID)
                                }
                                Button("Open Working Directory") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FilePath.workingDirectory.relativePath)
                                }
                                Button {
                                    Task {
                                        await clearWorkingDirectory()
                                    }
                                } label: {
                                    Text("Clear Working Directory").foregroundColor(.red)
                                }
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        #endif
                    }
                    Section("Debug") {
                        FormTextItem("Taiwan Flag Available", taiwanFlagAvailable.description)
                    }
                }
            }
        }
        .alertBinding($alert)
    }

    #if os(macOS)
        private func updateLoginItems(_ startAtLogin: Bool) {
            do {
                if startAtLogin {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }

                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                alert = Alert(error)
            }
        }
    #endif

    private func loadSettings() async {
        #if os(macOS)
            startAtLogin = SMAppService.mainApp.status == .enabled
            keepMenuBarInBackground = await SharedPreferences.menuBarExtraInBackground.get()
        #endif
        alwaysOn = await SharedPreferences.alwaysOn.get()
        disableMemoryLimit = await SharedPreferences.disableMemoryLimit.get()
        #if !os(tvOS)
            includeAllNetworks = await SharedPreferences.includeAllNetworks.get()
        #endif
        if ApplicationLibrary.inPreview {
            version = "<redacted>"
            dataSize = LibboxFormatBytes(1000 * 1000 * 10)
            taiwanFlagAvailable = true
            isLoading = false
        } else {
            version = LibboxVersion()
            dataSize = "Loading..."
            taiwanFlagAvailable = !DeviceCensorship.isChinaDevice()
            isLoading = false
            await loadSettingsBackground()
        }
    }

    private nonisolated func loadSettingsBackground() async {
        let dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
        await MainActor.run {
            self.dataSize = dataSize
        }
    }

    private nonisolated func clearWorkingDirectory() async {
        try? FileManager.default.removeItem(at: FilePath.workingDirectory)
        await MainActor.run {
            isLoading = true
        }
    }

    private func updateAlwaysOn(_ newState: Bool) async {
        guard let profile = try? await ExtensionProfile.load() else {
            return
        }
        do {
            try await profile.updateAlwaysOn(newState)
        } catch {
            alert = Alert(error)
        }
    }
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
