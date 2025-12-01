import AppKit
import ApplicationLibrary
import Libbox
import Library
import SwiftUI

@MainActor
public class MainViewModel: BaseViewModel {
    @Published public var selection = NavigationPage.dashboard
    @Published public var importProfile: LibboxProfileContent?
    @Published public var importRemoteProfile: LibboxImportRemoteProfile?

    public func onAppear(environments: ExtensionEnvironments) {
        environments.postReload()
        #if !DEBUG
            if Variant.useSystemExtension {
                checkApplicationPath()
            }
        #endif
    }

    public func onControlActiveStateChange(_ newValue: ControlActiveState, environments: ExtensionEnvironments) {
        if newValue != .inactive {
            environments.postReload()
        }
    }

    public func onSelectionChange(_ newValue: NavigationPage, environments: ExtensionEnvironments) {
        if newValue == .logs {
            environments.connect()
        }
    }

    public func openSettings() {
        selection = .settings
    }

    public func openURL(_ url: URL) {
        if url.host == "import-remote-profile" {
            var error: NSError?
            importRemoteProfile = LibboxParseRemoteProfileImportLink(url.absoluteString, &error)
            if error != nil {
                return
            }
            if selection != .dashboard {
                selection = .dashboard
            }
        } else if url.pathExtension == "bpf" {
            Task {
                await importURLProfile(url)
            }
        } else {
            alert = AlertState(errorMessage: String(localized: "Handled unknown URL \(url.absoluteString)"))
        }
    }

    private func importURLProfile(_ url: URL) async {
        do {
            _ = url.startAccessingSecurityScopedResource()
            importProfile = try await .from(readURL(url))
            url.stopAccessingSecurityScopedResource()
        } catch {
            alert = AlertState(error: error)
            return
        }
        if selection != .dashboard {
            selection = .dashboard
        }
    }

    private nonisolated func readURL(_ url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    private func checkApplicationPath() {
        let directoryName = URL(filePath: Bundle.main.bundlePath).deletingLastPathComponent().pathComponents.last
        if directoryName != "Applications" {
            alert = AlertState(
                title: String(localized: "Wrong application location"),
                message: String(localized: "This app needs to be placed under the Applications folder to work."),
                dismissButton: .default(String(localized: "Ok")) {
                    NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
                    NSApp.terminate(nil)
                }
            )
        }
    }
}
