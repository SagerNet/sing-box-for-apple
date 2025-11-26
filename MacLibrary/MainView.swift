import ApplicationLibrary
import Library
import SwiftUI

@MainActor
public struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = MainViewModel()
    @State private var showCardManagement = false
    @State private var cardConfigurationVersion = 0

    private let profileEditor: (Binding<String>, Bool) -> AnyView = { text, isEditable in
        AnyView(CodeEditTextView(text: text, isEditable: isEditable))
    }

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
            .environment(\.cardConfigurationVersion, cardConfigurationVersion)
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
                    Menu {
                        Button {
                            showCardManagement = true
                        } label: {
                            Label("Dashboard Items", systemImage: "square.grid.2x2")
                        }
                    } label: {
                        Label("Others", systemImage: "ellipsis.circle")
                    }
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
        .environment(\.profileEditor, profileEditor)
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL(perform: viewModel.openURL)
        .sheet(isPresented: $showCardManagement) {
            CardManagementSheet(configurationVersion: $cardConfigurationVersion)
                .frame(minWidth: 400, minHeight: 400)
        }
    }
}
