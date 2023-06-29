import Foundation
import Libbox
import Library
import SwiftUI
#if os(macOS)
    import ServiceManagement
#endif

public struct SettingView: View {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @State private var isLoading = true

    #if os(macOS)
        @State private var startAtLogin = false
        @Environment(\.showMenuBarExtra) private var showMenuBarExtra
    #endif

    @State private var disableMemoryLimit = false
    @State private var version = ""
    @State private var dataSize = ""

    @State private var errorPresented = false
    @State private var errorMessage = ""

    public init() {}

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    #if os(macOS)
                        Section("MacOS") {
                            Toggle("Start At Login", isOn: $startAtLogin)
                                .onChange(of: startAtLogin) { newValue in
                                    Task.detached {
                                        updateLoginItems(newValue)
                                    }
                                }
                            Toggle("Show in Menu Bar", isOn: showMenuBarExtra)
                                .onChange(of: showMenuBarExtra.wrappedValue) { newValue in
                                    Task.detached {
                                        SharedPreferences.showMenuBarExtra = newValue
                                    }
                                }
                        }
                    #endif
                    Section("Packet Tunnel") {
                        Toggle("Disable Memory Limit", isOn: $disableMemoryLimit)
                            .onChange(of: disableMemoryLimit) { newValue in
                                Task.detached {
                                    SharedPreferences.disableMemoryLimit = newValue
                                }
                            }
                    }
                    Section("Core") {
                        FormTextItem("Version", version)
                        FormTextItem("Data Size", dataSize)
                        #if os(iOS)
                            NavigationLink(destination: ServiceLogView()) {
                                Text("View Service Log")
                            }
                        #elseif os(macOS)
                            Button("View Service Log") {
                                openWindow(id: ServiceLogView.windowID)
                            }
                        #endif
                        Button("Clear Working Directory") {
                            Task.detached {
                                clearWorkingDirectory()
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .alert(isPresented: $errorPresented) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Ok"))
            )
        }
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
                errorMessage = error.localizedDescription
                errorPresented = true
            }
        }
    #endif

    private func loadSettings() async {
        #if os(macOS)
            startAtLogin = SMAppService.mainApp.status == .enabled
        #endif
        disableMemoryLimit = SharedPreferences.disableMemoryLimit
        version = LibboxVersion()
        dataSize = "Loading..."
        isLoading = false
        dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
    }

    private func clearWorkingDirectory() {
        try? FileManager.default.removeItem(at: FilePath.workingDirectory)
        isLoading = true
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
