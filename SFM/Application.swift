import ApplicationLibrary
import Library
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate

    @State private var showMenuBarExtra = false
    @State private var isMenuPresented = false

    var body: some Scene {
        Window("sing-box", id: "main", content: {
            MainView()
                .onAppear {
                    Task.detached {
                        await initialize()
                    }
                }
                .environment(\.showMenuBarExtra, $showMenuBarExtra)
        })
        .commands {
            if showMenuBarExtra {
                CommandGroup(replacing: .appTermination) {
                    Button("Quit sing-box") {
                        hide(closeApp: true)
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                }
                CommandGroup(replacing: .saveItem) {
                    Button("Close") {
                        hide(closeApp: false)
                    }
                    .keyboardShortcut("w", modifiers: [.command])
                }
            }
            SidebarCommands()
        }

        Window("New Profile", id: NewProfileView.windowID) {
            NewProfileView()
        }

        WindowGroup("Edit Profile", id: EditProfileWindowView.windowID, for: Int64.self) { profileID in
            EditProfileWindowView(profileID.wrappedValue)
        }.commandsRemoved()

        WindowGroup("Edit Content", id: EditProfileContentView.windowID, for: EditProfileContentView.Context.self) { context in
            EditProfileContentView(context.wrappedValue)
        }.commandsRemoved()

        Window("Service Log", id: ServiceLogView.windowID) {
            ServiceLogView()
        }
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuView(isMenuPresented: $isMenuPresented)
        } label: {
            Image(systemName: "network.badge.shield.half.filled")
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)
    }

    private func initialize() async {
        let initialShowMenuBarExtra = SharedPreferences.showMenuBarExtra
        await MainActor.run {
            showMenuBarExtra = initialShowMenuBarExtra
        }
    }

    private func hide(closeApp: Bool) {
        if closeApp || NSApp.keyWindow?.identifier?.rawValue == "main" {
            let transformState = ProcessApplicationTransformState(kProcessTransformToUIElementApplication)
            var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            TransformProcessType(&psn, transformState)
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.keyWindow?.close()
    }
}
