import ApplicationLibrary
import Libbox
import Library
import SwiftUI

public struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var selection = NavigationPage.dashboard
    @State private var extensionProfile: ExtensionProfile?
    @State private var profileLoading = true
    @State private var logClient: LogClient!
    @State private var importProfile: LibboxProfileContent?
    @State private var importRemoteProfile: LibboxImportRemoteProfile?
    @State private var alert: Alert?

    public init() {}
    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if profileLoading {
                ProgressView().onAppear {
                    Task {
                        logClient = LogClient(SharedPreferences.maxLogLines)
                        await loadProfile()
                    }
                }
            } else {
                selection.contentView
                    .navigationTitle(selection.title)
            }
        }
        #if !DEBUG
        .onAppear {
                if Variant.useSystemExtension {
                    Task.detached {
                        checkApplicationPath()
                    }
                }
            }
        #endif
            .alertBinding($alert)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    StartStopButton()
                }
            }
            .onChangeCompat(of: controlActiveState) { newValue in
                if newValue != .inactive {
                    Task {
                        await loadProfile()
                        connectLog()
                    }
                }
            }
            .onChangeCompat(of: selection) { value in
                if value == .logs {
                    connectLog()
                }
            }
            .formStyle(.grouped)
            .environment(\.selection, $selection)
            .environment(\.extensionProfile, $extensionProfile)
            .environment(\.logClient, $logClient)

            .environment(\.importProfile, $importProfile)
            .environment(\.importRemoteProfile, $importRemoteProfile)
            .handlesExternalEvents(preferring: [], allowing: ["*"])
            .onOpenURL(perform: openURL)
    }

    private func openURL(url: URL) {
        if url.host == "import-remote-profile" {
            var error: NSError?
            importRemoteProfile = LibboxParseRemoteProfileImportLink(url.absoluteString, &error)
            if error != nil {
                return
            }
            if selection != .profiles {
                selection = .profiles
            }
        } else if url.pathExtension == "bpf" {
            do {
                _ = url.startAccessingSecurityScopedResource()
                importProfile = try .from(Data(contentsOf: url))
                url.stopAccessingSecurityScopedResource()
            } catch {
                alert = Alert(error)
                return
            }
            if selection != .profiles {
                selection = .profiles
            }
        } else {
            alert = Alert(errorMessage: "Handled unknown URL \(url.absoluteString)")
        }
    }

    private func loadProfile() async {
        defer {
            profileLoading = false
        }
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil {
                newProfile.register()
                extensionProfile = newProfile
            }
        } else {
            extensionProfile = nil
        }
    }

    private func connectLog() {
        guard let profile = extensionProfile else {
            return
        }
        guard let logClient else {
            return
        }
        if profile.status.isConnected, !logClient.isConnected {
            logClient.reconnect()
        }
    }

    private func checkApplicationPath() {
        let directoryName = URL(filePath: Bundle.main.bundlePath).deletingLastPathComponent().pathComponents.last
        if directoryName != "Applications" {
            alert = Alert(
                title: Text("Wrong application location"),
                message: Text("This app needs to be placed under ~/Applications to work."),
                dismissButton: .default(Text("Ok")) {
                    NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
                    NSApp.terminate(nil)
                }
            )
        }
    }
}
