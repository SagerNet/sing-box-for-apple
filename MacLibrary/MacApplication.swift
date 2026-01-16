import ApplicationLibrary
import Libbox
import Library
import NetworkExtension
import SwiftUI

public struct MacApplication: Scene {
    @State private var isInitialized = false
    @State private var showMenuBarExtra = false
    @State private var menuBarExtraSpeedMode = MenuBarExtraSpeedMode.enabled.rawValue
    @StateObject private var environments = ExtensionEnvironments()
    @State private var statusBarController: StatusBarController?

    private let profileEditor: (Binding<String>, Bool) -> AnyView = { text, isEditable in
        AnyView(ProfileEditorWrapperView(text: text, isEditable: isEditable))
    }

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
                .environment(\.menuBarExtraSpeedMode, $menuBarExtraSpeedMode)
                .environmentObject(environments)
                .onChangeCompat(of: showMenuBarExtra) { newValue in
                    statusBarController?.updateVisibility(newValue)
                    Task {
                        await SharedPreferences.showMenuBarExtra.set(newValue)
                    }
                }
                .onChangeCompat(of: menuBarExtraSpeedMode) { newValue in
                    statusBarController?.updateSpeedMode(newValue)
                    Task {
                        await SharedPreferences.menuBarExtraSpeedMode.set(newValue)
                    }
                }
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

        WindowGroup(for: EditProfileContentView.Context.self) { $context in
            EditProfileContentWindow(context: context)
                .environment(\.profileEditor, profileEditor)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 500)
    }

    private func initialize() async {
        guard !isInitialized else { return }
        isInitialized = true
        showMenuBarExtra = await SharedPreferences.showMenuBarExtra.get()
        menuBarExtraSpeedMode = await SharedPreferences.menuBarExtraSpeedMode.get()
        statusBarController = StatusBarController(environments: environments)
        statusBarController?.updateVisibility(showMenuBarExtra)
        statusBarController?.updateSpeedMode(menuBarExtraSpeedMode)
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
