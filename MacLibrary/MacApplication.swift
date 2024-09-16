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
                    Task {
                        await initialize()
                    }
                }
                .environment(\.showMenuBarExtra, $showMenuBarExtra)
                .environmentObject(environments)
        })
        .windowResizability(.contentSize)
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    environments.openSettings.send()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuView(isMenuPresented: $isMenuPresented)
                .environmentObject(environments)
        } label: {
            Image("MenuIcon")
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)
    }

    private func initialize() async {
        showMenuBarExtra = await SharedPreferences.showMenuBarExtra.get()
    }

    private func hide(closeApp: Bool) {
        Task {
            if await SharedPreferences.menuBarExtraInBackground.get() {
                hide0(closeApp: closeApp)
            } else {
                if closeApp {
                    NSApp.terminate(nil)
                } else {
                    NSApp.keyWindow?.close()
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
