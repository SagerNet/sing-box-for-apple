import ApplicationLibrary
import Libbox
import Library
import SwiftUI

@MainActor
public struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var selection = NavigationPage.dashboard
    @State private var importProfile: LibboxProfileContent?
    @State private var importRemoteProfile: LibboxImportRemoteProfile?
    @State private var alert: Alert?

    public init() {}
    public var body: some View {
        if ApplicationLibrary.inPreview {
            body1.frame(width: 1280, height: 750, alignment: .topLeading)
        } else {
            body1
        }
    }

    private var body1: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            NavigationStack {
                selection.contentView
                    .navigationTitle(selection.title)
            }
        }
        .onAppear {
            environments.postReload()
            #if !DEBUG
                if Variant.useSystemExtension {
                    Task {
                        checkApplicationPath()
                    }
                }
            #endif
        }
        .alertBinding($alert)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StartStopButton()
            }
        }
        .onChangeCompat(of: controlActiveState) { newValue in
            if newValue != .inactive {
                environments.postReload()
            }
        }
        .onChangeCompat(of: selection) { value in
            if value == .logs {
                environments.connectLog()
            }
        }
        .onReceive(environments.openSettings) {
            selection = .settings
        }
        .formStyle(.grouped)
        .environment(\.selection, $selection)
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
            Task {
                await importURLProfile(url)
            }
        } else {
            alert = Alert(errorMessage: String(localized: "Handled unknown URL \(url.absoluteString)"))
        }
    }

    private func importURLProfile(_ url: URL) async {
        do {
            _ = url.startAccessingSecurityScopedResource()
            importProfile = try await .from(readURL(url))
            url.stopAccessingSecurityScopedResource()
        } catch {
            alert = Alert(error)
            return
        }
        if selection != .profiles {
            selection = .profiles
        }
    }

    private nonisolated func readURL(_ url: URL) async throws -> Data {
        try Data(contentsOf: url)
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
