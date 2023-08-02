import ApplicationLibrary
import Library
import SwiftUI

public struct SidebarView: View {
    @Environment(\.selection) private var selection
    @Environment(\.extensionProfile) private var extensionProfile

    public init() {}
    public var body: some View {
        VStack {
            if let profile = extensionProfile.wrappedValue {
                SidebarView0().environmentObject(profile)
            } else {
                SidebarView1()
            }
        }.frame(minWidth: 150)
    }

    struct SidebarView0: View {
        @Environment(\.selection) private var selection
        @EnvironmentObject private var extensionProfile: ExtensionProfile

        var body: some View {
            VStack {
                if extensionProfile.status.isConnectedStrict {
                    List(selection: selection) {
                        Section(NavigationPage.dashboard.title) {
                            Label("Overview", systemImage: "text.and.command.macwindow").tag(NavigationPage.dashboard)
                            NavigationPage.groups.label.tag(NavigationPage.groups)
                        }
                        Divider()
                        ForEach(NavigationPage.macosDefaultPages, id: \.self) { it in
                            it.label
                        }
                    }
                } else {
                    List(NavigationPage.allCases.filter { it in
                        it.visible(extensionProfile)
                    }, selection: selection) { it in
                        it.label
                    }
                }
            }
            .onChangeCompat(of: extensionProfile.status) {
                if !selection.wrappedValue.visible(extensionProfile) {
                    selection.wrappedValue = NavigationPage.dashboard
                }
            }
        }
    }

    struct SidebarView1: View {
        @Environment(\.selection) private var selection

        var body: some View {
            List(NavigationPage.allCases.filter { it in
                it.visible(nil)
            }, selection: selection) { it in
                it.label
            }
        }
    }
}
