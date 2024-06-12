import ApplicationLibrary
import Libbox
import Library
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var selection = NavigationPage.dashboard
    @State private var importProfile: LibboxProfileContent?
    @State private var importRemoteProfile: LibboxImportRemoteProfile?
    @State private var alert: Alert?

    var body: some View {
        if ApplicationLibrary.inPreview {
            body1.preferredColorScheme(.dark)
        } else {
            body1
        }
    }

    var body1: some View {
        TabView(selection: $selection) {
            ForEach(NavigationPage.allCases, id: \.self) { page in
                NavigationStackCompat {
                    page.contentView
                        .navigationTitle(page.title)
                }
                .tag(page)
                .tabItem { page.label }
            }
        }
        .onAppear {
            environments.postReload()
        }
        .alertBinding($alert)
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                environments.postReload()
            }
        }
        .onChangeCompat(of: selection) { newValue in
            if newValue == .logs {
                environments.connectLog()
            }
        }
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
            if let error {
                alert = Alert(error)
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
            alert = Alert(errorMessage: String(localized: "Handled unknown URL \(url.absoluteString)"))
        }
    }
}
