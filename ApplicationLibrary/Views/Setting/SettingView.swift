import Foundation
import Libbox
import Library
import SwiftUI
#if os(macOS)
    import AppKit
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
        @State private var keepMenuBarInBackground = false
    #endif

    @State private var disableMemoryLimit = false
    @State private var version = ""
    @State private var dataSize = ""
    @State private var taiwanFlagAvailable = false

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
                                        if !newValue {
                                            keepMenuBarInBackground = false
                                        }
                                    }
                                }
                            if showMenuBarExtra.wrappedValue {
                                Toggle("Keep Menu Bar in Background", isOn: $keepMenuBarInBackground)
                                    .onChange(of: keepMenuBarInBackground) { newValue in
                                        Task.detached {
                                            SharedPreferences.menuBarExtraInBackground = newValue
                                        }
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
                            Button("Clear Working Directory") {
                                Task.detached {
                                    clearWorkingDirectory()
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
                                    Task.detached {
                                        clearWorkingDirectory()
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
            keepMenuBarInBackground = SharedPreferences.menuBarExtraInBackground
        #endif
        disableMemoryLimit = SharedPreferences.disableMemoryLimit
        version = LibboxVersion()
        if ApplicationLibrary.inPreview {
            dataSize = LibboxFormatBytes(1024 * 1024 * 10)
            taiwanFlagAvailable = true
            isLoading = false
        } else {
            dataSize = "Loading..."
            taiwanFlagAvailable = !DeviceCensorship.isChinaDevice()
            isLoading = false
            dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
        }
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
