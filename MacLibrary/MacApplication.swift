import ApplicationLibrary
import Library
import SwiftUI

public struct MacApplication: Scene {
    @State private var showMenuBarExtra = false
    @State private var isMenuPresented = false
    @StateObject private var environments = ExtensionEnvironments()

    public init() {}
    public var body: some Scene {
        Window("sing-box", id: "main", content: {
            MainView()
                .onAppear {
                    Task.detached {
                        await initialize()
                    }
                }
                .environment(\.showMenuBarExtra, $showMenuBarExtra)
                .environmentObject(environments)
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

        WindowGroup("New Profile", id: NewProfileView.windowID, for: NewProfileView.ImportRequest.self) { importRequest in
            NewProfileView(importRequest.wrappedValue)
        }.commandsRemoved()

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
            Image("MenuIcon")
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)
    }

    private func initialize() {
        let initialShowMenuBarExtra = SharedPreferences.showMenuBarExtra
        DispatchQueue.main.async {
            showMenuBarExtra = initialShowMenuBarExtra
        }
    }

    private func hide(closeApp: Bool) {
        Task.detached {
            if SharedPreferences.menuBarExtraInBackground {
                DispatchQueue.main.async {
                    hide0(closeApp: closeApp)
                }
            } else {
                DispatchQueue.main.async {
                    if closeApp {
                        NSApp.terminate(nil)
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
            }
        }
    }

    private func hide0(closeApp: Bool) {
        if closeApp || NSApp.keyWindow?.identifier?.rawValue == "main" {
            let transformState = ProcessApplicationTransformState(kProcessTransformToUIElementApplication)
            var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            TransformProcessType(&psn, transformState)
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.keyWindow?.close()
    }
}
