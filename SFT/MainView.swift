import ApplicationLibrary
import Foundation
import Libbox
import Library
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var selection: NavigationPage = {
        if Variant.screenshotMode,
           let pageValue = ProcessInfo.processInfo.environment["SCREENSHOT_PAGE"],
           let page = NavigationPage(snapshotValue: pageValue)
        {
            return page
        }
        return .dashboard
    }()

    @State private var importProfile: LibboxProfileContent?
    @State private var importRemoteProfile: LibboxImportRemoteProfile?

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
            if Variant.screenshotMode,
               let pageValue = ProcessInfo.processInfo.environment["SCREENSHOT_PAGE"],
               let page = NavigationPage(snapshotValue: pageValue)
            {
                selection = page
            }
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
        .globalChecks()
        .environment(\.selection, $selection)
        .environment(\.importProfile, $importProfile)
        .environment(\.importRemoteProfile, $importRemoteProfile)
    }
}
