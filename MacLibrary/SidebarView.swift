import ApplicationLibrary
import Library
import SwiftUI

private struct SidebarContentView: View {
    @Binding var selection: NavigationPage
    @Binding var localSelection: NavigationPage
    @ObservedObject var profile: ExtensionProfile
    var environments: ExtensionEnvironments

    private var hasGroups: Bool {
        Variant.screenshotMode || environments.commandClient.groups?.isEmpty == false
    }

    var body: some View {
        List(selection: $localSelection) {
            if profile.status.isConnectedStrict {
                Section(NavigationPage.dashboard.title) {
                    Label("Overview", systemImage: "text.and.command.macwindow")
                        .tint(.textColor)
                        .tag(NavigationPage.dashboard)
                    if hasGroups {
                        NavigationPage.groups.label.tag(NavigationPage.groups)
                    }
                    NavigationPage.connections.label.tag(NavigationPage.connections)
                }
                ForEach(NavigationPage.macosDefaultPages, id: \.self) { it in
                    it.label
                }
            } else {
                ForEach(NavigationPage.allCases.filter { $0.visible(profile) }, id: \.self) { it in
                    it.label
                }
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .onAppear {
            localSelection = selection
        }
        .onChangeCompat(of: selection) { newValue in
            if localSelection != newValue {
                localSelection = newValue
            }
        }
        .onChangeCompat(of: localSelection) { newValue in
            if selection != newValue {
                Task { @MainActor in
                    selection = newValue
                }
            }
        }
        .onChangeCompat(of: profile.status) {
            if !localSelection.visible(profile) {
                Task { @MainActor in
                    localSelection = .dashboard
                }
            }
        }
        .onReceive(environments.commandClient.$groups) { groups in
            if localSelection == .groups, groups?.isEmpty != false {
                Task { @MainActor in
                    localSelection = .dashboard
                }
            }
        }
    }
}

public struct SidebarView: View {
    @Binding var selection: NavigationPage
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var localSelection: NavigationPage = .dashboard

    public init(selection: Binding<NavigationPage>) {
        _selection = selection
    }

    public var body: some View {
        if environments.extensionProfileLoading {
            ProgressView()
        } else if let profile = environments.extensionProfile {
            SidebarContentView(
                selection: $selection,
                localSelection: $localSelection,
                profile: profile,
                environments: environments
            )
        } else {
            disconnectedContent
        }
    }

    private var disconnectedContent: some View {
        List(selection: $localSelection) {
            ForEach(NavigationPage.allCases.filter { $0.visible(nil) }, id: \.self) { it in
                it.label
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .onAppear {
            localSelection = selection
        }
        .onChangeCompat(of: selection) { newValue in
            if localSelection != newValue {
                localSelection = newValue
            }
        }
        .onChangeCompat(of: localSelection) { newValue in
            if selection != newValue {
                Task { @MainActor in
                    selection = newValue
                }
            }
        }
    }
}
