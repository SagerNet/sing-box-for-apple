#if os(macOS)

    import AppKit
    import Library
    import ServiceManagement
    import SwiftUI

    public struct MacAppView: View {
        @State private var isLoading = true

        @State private var startAtLogin = false
        @Environment(\.showMenuBarExtra) private var showMenuBarExtra
        @State private var menuBarExtraInBackground = false

        @State private var alert: Alert?

        public init() {}
        public var body: some View {
            viewBuilder {
                if isLoading {
                    ProgressView().onAppear {
                        Task {
                            await loadSettings()
                        }
                    }
                } else {
                    FormView {
                        FormSection {
                            Toggle("Start At Login", isOn: $startAtLogin)
                                .onChangeCompat(of: startAtLogin) { newValue in
                                    Task {
                                        updateLoginItems(newValue)
                                    }
                                }
                        } footer: {
                            Text("Launch the application when the system is logged in. If enabled at the same time as `Show in Menu Bar` and `Keep Menu Bar in Background`, the application interface will not be opened automatically.")
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
                    }
                }
            }
            .alertBinding($alert)
            .navigationTitle("App")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        private func loadSettings() async {
            startAtLogin = SMAppService.mainApp.status == .enabled
            menuBarExtraInBackground = await SharedPreferences.menuBarExtraInBackground.get()
            isLoading = false
        }

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
                alert = Alert(error)
            }
        }

        private func updateSystemExtension() async {
            do {
                if let result = try await SystemExtension.install(forceUpdate: true) {
                    switch result {
                    case .completed:
                        alert = Alert(
                            title: Text("Update"),
                            message: Text("System Extension updated."),
                            dismissButton: .default(Text("Ok")) {}
                        )
                    case .willCompleteAfterReboot:
                        alert = Alert(
                            title: Text("Update"),
                            message: Text("Reboot required."),
                            dismissButton: .default(Text("Ok")) {}
                        )
                    }
                }
            } catch {
                alert = Alert(error)
            }
        }

        private func uninstallSystemExtension() async {
            do {
                if let result = try await SystemExtension.uninstall() {
                    switch result {
                    case .completed:
                        alert = Alert(
                            title: Text("Uninstall"),
                            message: Text("System Extension removed."),
                            dismissButton: .default(Text("Ok")) {}
                        )
                    case .willCompleteAfterReboot:
                        alert = Alert(
                            title: Text("Uninstall"),
                            message: Text("Reboot required."),
                            dismissButton: .default(Text("Ok")) {}
                        )
                    }
                }
            } catch {
                alert = Alert(error)
            }
        }
    }

#endif
