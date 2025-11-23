import ApplicationLibrary
import Libbox
import Library
import NetworkExtension
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
        viewBuilder {
            if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
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
                .tabViewBottomAccessory {
                    HStack(spacing: 12) {
                        if let profile = environments.extensionProfile {
                            StatusText(profile: profile)
                        }
                        Spacer()
                        StartStopButton()
                    }
                    .padding(.horizontal)
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
                        environments.connect()
                    }
                }
                .environment(\.selection, $selection)
                .environment(\.importProfile, $importProfile)
                .environment(\.importRemoteProfile, $importRemoteProfile)
                .handlesExternalEvents(preferring: [], allowing: ["*"])
                .onOpenURL(perform: openURL)
            } else {
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
                        environments.connect()
                    }
                }
                .environment(\.selection, $selection)
                .environment(\.importProfile, $importProfile)
                .environment(\.importRemoteProfile, $importRemoteProfile)
                .handlesExternalEvents(preferring: [], allowing: ["*"])
                .onOpenURL(perform: openURL)
            }
        }
    }

    private struct StatusText: View {
        @ObservedObject var profile: ExtensionProfile

        var body: some View {
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        private var statusText: String {
            switch profile.status {
            case .invalid:
                return "Invalid"
            case .disconnected:
                return "Stopped"
            case .connecting:
                return "Starting"
            case .connected:
                return "Started"
            case .reasserting:
                return "Reasserting"
            case .disconnecting:
                return "Stopping"
            @unknown default:
                return "Unknown"
            }
        }
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
