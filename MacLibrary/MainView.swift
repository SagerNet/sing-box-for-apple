import ApplicationLibrary
import Library
import SwiftUI

@MainActor
public struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = MainViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(150)
        } detail: {
            NavigationStack {
                viewModel.selection.contentView
                    .navigationTitle(viewModel.selection.title)
            }
            .navigationSplitViewColumnWidth(650)
        }
        .frame(minHeight: 500)
        .onAppear {
            viewModel.onAppear(environments: environments)
        }
        .alertBinding($viewModel.alert)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StartStopButton()
            }
            if viewModel.selection == .dashboard {
                ToolbarItem(placement: .automatic) {
                    DashboardMenu()
                }
            }
        }
        .onChangeCompat(of: controlActiveState) { newValue in
            viewModel.onControlActiveStateChange(newValue, environments: environments)
        }
        .onChangeCompat(of: viewModel.selection) { value in
            viewModel.onSelectionChange(value, environments: environments)
        }
        .onReceive(environments.openSettings) {
            viewModel.openSettings()
        }
        .environment(\.selection, $viewModel.selection)
        .environment(\.importProfile, $viewModel.importProfile)
        .environment(\.importRemoteProfile, $viewModel.importRemoteProfile)
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL(perform: viewModel.openURL)
    }
}
