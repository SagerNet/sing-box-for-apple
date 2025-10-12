import ApplicationLibrary
import Libbox
import Library
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var selection = NavigationPage.dashboard

    var body: some View {
        TabView(selection: $selection) {
            ForEach(NavigationPage.allCases, id: \.self) { page in
                NavigationStackCompat {
                    page.contentView
                        .focusSection()
                }
                .tag(page)
                .tabItem { page.label }
            }
        }
        .onAppear {
            environments.postReload()
        }
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
    }
}
