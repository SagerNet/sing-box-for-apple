import ApplicationLibrary
import Library
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) var scenePhase

    @State private var selection = NavigationPage.dashboard
    @State private var extensionProfile: ExtensionProfile?
    @State private var profileLoading = true
    @State private var logClient: LogClient!

    @State private var serviceNotificationTitle = ""
    @State private var serviceNotificationContent = ""
    @State private var serviceNotificationPresented = false

    var body: some View {
        viewBuilder {
            if profileLoading {
                ProgressView().onAppear {
                    Task.detached {
                        logClient = LogClient(SharedPreferences.maxLogLines)
                        await loadProfile()
                    }
                }
            } else {
                ContentView()
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
        .onChange(of: scenePhase, perform: { newValue in
            if newValue == .active {
                Task.detached {
                    await loadProfile()
                }
            }
        })
        .environment(\.selection, $selection)
        .environment(\.extensionProfile, $extensionProfile)
        .environment(\.logClient, $logClient)
        .preferredColorScheme(.dark)
    }

    private func loadProfile() async {
        defer {
            profileLoading = false
        }
        if ApplicationLibrary.inPreview {
            return
        }
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil || extensionProfile?.status == .invalid {
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
