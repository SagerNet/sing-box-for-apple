import ApplicationLibrary
import Library
import SwiftUI

public struct SidebarView: View {
    @Binding var selection: NavigationPage
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init(selection: Binding<NavigationPage>) {
        _selection = selection
    }

    public var body: some View {
        if ApplicationLibrary.inPreview {
            sidebarContent(isConnected: true, profile: nil)
        } else if environments.extensionProfileLoading {
            ProgressView()
        } else if let profile = environments.extensionProfile {
            sidebarContent(isConnected: profile.status.isConnectedStrict, profile: profile)
                .onChangeCompat(of: profile.status) {
                    if !selection.visible(profile) {
                        DispatchQueue.main.async {
                            selection = .dashboard
                        }
                    }
                }
        } else {
            sidebarContent(isConnected: false, profile: nil)
        }
    }

    @ViewBuilder
    private func sidebarContent(isConnected: Bool, profile: ExtensionProfile?) -> some View {
        List(selection: $selection) {
            if isConnected {
                Section(NavigationPage.dashboard.title) {
                    Label("Overview", systemImage: "text.and.command.macwindow")
                        .tint(.textColor)
                        .tag(NavigationPage.dashboard)
                    NavigationPage.groups.label.tag(NavigationPage.groups)
                    if Variant.isBeta {
                        NavigationPage.connections.label.tag(NavigationPage.connections)
                    }
                }
                Divider()
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
    }
}
