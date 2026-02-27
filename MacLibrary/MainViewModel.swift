import AppKit
import ApplicationLibrary
import Libbox
import Library
import SwiftUI

@MainActor
public class MainViewModel: BaseViewModel {
    @Published public var selection: NavigationPage
    @Published public var importProfile: LibboxProfileContent?
    @Published public var importRemoteProfile: LibboxImportRemoteProfile?

    public init(selection: NavigationPage = .dashboard) {
        self.selection = selection
        super.init()
    }

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
            if let error {
                alert = AlertState(action: "parse remote profile import link", error: error)
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
            importProfile = try await url.withSecurityScopedAccess {
                try await .from(readURL(url))
            }
        } catch {
            alert = AlertState(action: "import profile from URL", error: error)
        }
    }

    private nonisolated func readURL(_ url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    private func checkApplicationPath() {
        let directoryName = URL(filePath: Bundle.main.bundlePath).deletingLastPathComponent().pathComponents.first
        if directoryName != "Applications" {
            alert = AlertState(
                title: String(localized: "Wrong application location"),
                message: String(localized: "This app needs to be placed under the Applications folder to work."),
                primaryButton: .default(String(localized: "Move to Applications")) { [self] in
                    moveToApplications()
                },
                secondaryButton: .cancel(String(localized: "Quit")) {
                    NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
                    NSApp.terminate(nil)
                }
            )
        }
    }

    private func moveToApplications() {
        let source = Bundle.main.bundlePath
        let appName = URL(filePath: source).lastPathComponent
        let dest = "/Applications/\(appName)"

        let script = """
        do shell script "rm -rf '\(dest)'; mv '\(source)' '\(dest)'" with administrator privileges
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return }
        appleScript.executeAndReturnError(&error)

        if let error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            alert = AlertState(errorMessage: msg)
            return
        }

        let url = URL(filePath: dest)
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        NSApp.terminate(nil)
    }
}
