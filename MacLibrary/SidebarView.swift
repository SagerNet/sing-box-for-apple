import ApplicationLibrary
import Library
import SwiftUI

public struct SidebarView: View {
    @Binding var selection: NavigationPage
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var localSelection: NavigationPage = .dashboard

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
                .onReceive(profile.$status) { _ in }
                .onChangeCompat(of: profile.status) {
                    if !localSelection.visible(profile) {
                        Task { @MainActor in
                            localSelection = .dashboard
                        }
                    }
                }
        } else {
            sidebarContent(isConnected: false, profile: nil)
        }
    }

    @ViewBuilder
    private func sidebarContent(isConnected: Bool, profile: ExtensionProfile?) -> some View {
        List(selection: $localSelection) {
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
