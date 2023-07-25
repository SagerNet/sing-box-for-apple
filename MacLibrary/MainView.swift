import ApplicationLibrary
import Library
import SwiftUI

public struct MainView: View {
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var selection = NavigationPage.dashboard
    @State private var extensionProfile: ExtensionProfile?
    @State private var profileLoading = true
    @State private var logClient: LogClient!

    @State private var dialogTitle = ""
    @State private var dialogContent = ""
    @State private var dialogAction: (() -> Void)?
    @State private var dialogPresented = false

    public init() {}
    public var body: some View {
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
        #if !DEBUG
        .onAppear {
                if Variant.useSystemExtension {
                    Task.detached {
                        checkApplicationPath()
                    }
                }
            }
        #endif
            .alert(isPresented: $dialogPresented, content: {
                Alert(
                    title: Text(dialogTitle),
                    message: Text(dialogContent),
                    dismissButton: .default(Text("Ok"), action: dialogAction)
                )
            })
            .onAppear {
                ServiceNotification.setServiceNotificationListener { notification in
                    dialogTitle = notification.title
                    dialogContent = notification.body
                    dialogAction = nil
                    dialogPresented = true
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

    private func checkApplicationPath() {
        let directoryName = URL(filePath: Bundle.main.bundlePath).deletingLastPathComponent().pathComponents.last
        if directoryName != "Applications" {
            dialogTitle = "Wrong application location"
            dialogContent = "This app needs to be placed under ~/Applications to work."
            dialogAction = {
                NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
                NSApp.terminate(nil)
            }
            dialogPresented = true
        }
    }
}
