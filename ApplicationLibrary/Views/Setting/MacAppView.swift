import Library
import SwiftUI

#if os(macOS)
    import AppKit
    import ServiceManagement
#endif

public struct AppView: View {
    @State private var isLoading = true

    @State private var startAtLogin = false
    @Environment(\.showMenuBarExtra) private var showMenuBarExtra
    @State private var menuBarExtraInBackground = false

    @State private var alert: AlertState?

    public init() {}
    public var body: some View {
        Group {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    #if os(macOS)
                        FormToggle("Start At Login", "Launch the application when the system is logged in. If enabled at the same time as `Show in Menu Bar` and `Keep Menu Bar in Background`, the application interface will not be opened automatically.", $startAtLogin) { newValue in
                            updateLoginItems(newValue)
                        }

                        Toggle("Show in Menu Bar", isOn: showMenuBarExtra)
                            .onChangeCompat(of: showMenuBarExtra.wrappedValue) { newValue in
                                Task {
                                    await SharedPreferences.showMenuBarExtra.set(newValue)
                                    if !newValue {
                                        menuBarExtraInBackground = false
                                    }
                                }
                            }

                        if showMenuBarExtra.wrappedValue {
                            Toggle("Keep Menu Bar in Background", isOn: $menuBarExtraInBackground)
                                .onChangeCompat(of: menuBarExtraInBackground) { newValue in
                                    Task {
                                        await SharedPreferences.menuBarExtraInBackground.set(newValue)
                                    }
                                }
                        }

                        if Variant.useSystemExtension {
                            Section("System Extension") {
                                FormButton {
                                    Task {
                                        await updateSystemExtension()
                                    }
                                } label: {
                                    Label("Update", systemImage: "arrow.down.doc.fill")
                                }
                                FormButton(role: .destructive) {
                                    Task {
                                        await uninstallSystemExtension()
                                    }
                                } label: {
                                    Label("Uninstall", systemImage: "trash.fill").foregroundColor(.red)
                                }
                            }
                        }
                    #endif
                }
            }
        }
        .alert($alert)
        .navigationTitle("App")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadSettings() async {
        #if os(macOS)
            startAtLogin = SMAppService.mainApp.status == .enabled
            menuBarExtraInBackground = await SharedPreferences.menuBarExtraInBackground.get()
        #endif
        isLoading = false
    }

    #if os(macOS)

        private func updateLoginItems(_ startAtLogin: Bool) {
            do {
                if startAtLogin {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }

                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                alert = AlertState(error: error)
            }
        }

        private func updateSystemExtension() async {
            do {
                if let result = try await SystemExtension.install(forceUpdate: true) {
                    switch result {
                    case .completed:
                        alert = AlertState(
                            title: String(localized: "Update"),
                            message: String(localized: "System Extension updated.")
                        )
                    case .willCompleteAfterReboot:
                        alert = AlertState(
                            title: String(localized: "Update"),
                            message: String(localized: "Reboot required.")
                        )
                    }
                }
            } catch {
                alert = AlertState(error: error)
            }
        }

        private func uninstallSystemExtension() async {
            do {
                if let result = try await SystemExtension.uninstall() {
                    switch result {
                    case .completed:
                        alert = AlertState(
                            title: String(localized: "Uninstall"),
                            message: String(localized: "System Extension removed.")
                        )
                    case .willCompleteAfterReboot:
                        alert = AlertState(
                            title: String(localized: "Uninstall"),
                            message: String(localized: "Reboot required.")
                        )
                    }
                }
            } catch {
                alert = AlertState(error: error)
            }
        }

    #endif
}
