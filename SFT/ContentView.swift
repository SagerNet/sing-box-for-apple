import ApplicationLibrary
import Library
import SwiftUI

struct ContentView: View {
    @Environment(\.selection) private var selection
    @Environment(\.extensionProfile) private var extensionProfile

    var body: some View {
        viewBuilder {
            if let profile = extensionProfile.wrappedValue {
                ContentView0().environmentObject(profile)
            } else {
                ContentView1()
            }
        }
    }

    struct ContentView0: View {
        @Environment(\.selection) private var selection
        @EnvironmentObject private var extensionProfile: ExtensionProfile

        var body: some View {
            TabView(selection: selection) {
                ForEach(NavigationPage.allCases.filter { it in
                    it.visible(extensionProfile)
                }, id: \.self) { page in
                    NavigationStackCompat {
                        page.contentView
                            .focusSection()
                    }
                    .tag(page)
                    .tabItem { page.label }
                }
            }.onChangeCompat(of: extensionProfile.status) {
                if !selection.wrappedValue.visible(extensionProfile) {
                    selection.wrappedValue = NavigationPage.dashboard
                }
            }
        }
    }

    struct ContentView1: View {
        @Environment(\.selection) private var selection

        var body: some View {
            TabView(selection: selection) {
                ForEach(NavigationPage.allCases.filter { it in
                    it.visible(nil)
                }, id: \.self) { page in
                    NavigationStackCompat {
                        page.contentView
                            .focusSection()
                    }
                    .tag(page)
                    .tabItem { page.label }
                }
            }
        }
    }
}
