import ApplicationLibrary
import Library
import SwiftUI

struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var selection = NavigationPage.dashboard
    @State private var extensionProfile: ExtensionProfile?
    @State private var profileLoading = true
    @State private var logClient: LogClient!

    @State private var serviceNotificationTitle = ""
    @State private var serviceNotificationContent = ""
    @State private var serviceNotificationPresented = false

    var body: some View {
        NavigationSplitView {
            VStack {
                SidebarView()
            }
            .frame(minWidth: 150)
        } detail: {
            if profileLoading {
                ProgressView().onAppear {
                    Task {
                        logClient = LogClient(SharedPreferences.maxLogLines)
                        await loadProfile()
                    }
                }
            } else {
                selection.contentView
            }
        }
        .alert(isPresented: $serviceNotificationPresented, content: {
            Alert(
                title: Text(serviceNotificationTitle),
                message: Text(serviceNotificationContent),
                dismissButton: .default(Text("Ok"))
            )
        })
        .onAppear {
            ServiceNotification.setServiceNotificationListener { notification in
                serviceNotificationTitle = notification.title
                serviceNotificationContent = notification.body
                serviceNotificationPresented = true
            }
        }
        .onDisappear {
            ServiceNotification.removeServiceNotificationListener()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StartStopButton()
            }
        }
        .onChange(of: controlActiveState, perform: { newValue in
            if newValue != .inactive {
                Task {
                    await loadProfile()
                    connectLog()
                }
            }
        })
        .onChange(of: selection, perform: { value in
            if value == .logs {
                connectLog()
            }
        })
        .formStyle(.grouped)
        .environment(\.selection, $selection)
        .environment(\.extensionProfile, $extensionProfile)
        .environment(\.logClient, $logClient)
    }

    private func loadProfile() async {
        defer {
            profileLoading = false
        }
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil {
                newProfile.register()
                extensionProfile = newProfile
            }
        } else {
            extensionProfile = nil
        }
    }

    private func connectLog() {
        guard let profile = extensionProfile else {
            return
        }
        guard let logClient else {
            return
        }
        if profile.status.isConnected, !logClient.isConnected {
            logClient.reconnect()
        }
    }
}
