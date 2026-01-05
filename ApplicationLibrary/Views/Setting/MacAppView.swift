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
    #if os(macOS)

        @State private var rootHelperRegistrationStatus: SMAppService.Status = .notRegistered

    #endif

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

                            Section {
                                if rootHelperRegistrationStatus == .enabled {
                                    FormButton {
                                        Task {
                                            do {
                                                try HelperServiceManager.unregisterRootHelper()
                                                try await Task.sleep(for: .seconds(1))
                                                try HelperServiceManager.registerRootHelper()
                                                refreshHelperStatus()
                                            } catch {
                                                alert = AlertState(error: error)
                                            }
                                        }
                                    } label: {
                                        Label("Update", systemImage: "arrow.down.doc.fill")
                                    }
                                    FormButton(role: .destructive) {
                                        performHelperAction {
                                            try HelperServiceManager.unregisterRootHelper()
                                        }
                                    } label: {
                                        Label("Uninstall", systemImage: "trash.fill").foregroundColor(.red)
                                    }
                                } else if rootHelperRegistrationStatus == .requiresApproval {
                                    FormButton {
                                        openHelperSettings()
                                    } label: {
                                        Label("Enable", systemImage: "switch.2")
                                    }
                                } else {
                                    FormButton {
                                        performHelperAction {
                                            try HelperServiceManager.registerRootHelper()
                                        }
                                    } label: {
                                        Label("Install", systemImage: "square.and.arrow.down.fill")
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Helper Service")
                                    Text("This helper service provides process lookup for `process_name` and `process_path` routing rules, and manages the working directory.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
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
            if Variant.useSystemExtension {
                refreshHelperStatus()
            }
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

        private func performHelperAction(_ action: () throws -> Void) {
            do {
                try action()
                refreshHelperStatus()
            } catch {
                alert = AlertState(error: error)
            }
        }

        private func refreshHelperStatus() {
            rootHelperRegistrationStatus = HelperServiceManager.rootHelperStatus
        }

        private func openHelperSettings() {
            if #available(macOS 13.0, *) {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems"),
               NSWorkspace.shared.open(url)
            {
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }

    #endif
}
