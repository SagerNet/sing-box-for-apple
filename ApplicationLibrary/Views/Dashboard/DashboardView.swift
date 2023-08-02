import Library
import SwiftUI

public struct DashboardView: View {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
        @State private var isLoading = true
        @State private var systemExtensionInstalled = true
    #endif

    public init() {}
    public var body: some View {
        viewBuilder {
            #if os(macOS)
                if Variant.useSystemExtension {
                    viewBuilder {
                        if !systemExtensionInstalled {
                            FormView {
                                InstallSystemExtensionButton(reload)
                            }
                        } else {
                            DashboardView0()
                        }
                    }.onAppear(perform: reload)
                } else {
                    DashboardView0()
                }
            #else
                DashboardView0()
            #endif
        }
        #if os(macOS)
        .onChangeCompat(of: controlActiveState) { newValue in
            if newValue != .inactive {
                if Variant.useSystemExtension {
                    if !isLoading {
                        reload()
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
        private func reload() {
            Task {
                systemExtensionInstalled = await SystemExtension.isInstalled()
                isLoading = false
            }
        }
    #endif

    struct DashboardView0: View {
        @Environment(\.extensionProfile) private var extensionProfile
        var body: some View {
            if ApplicationLibrary.inPreview {
                ActiveDashboardView()
            } else if let profile = extensionProfile.wrappedValue {
                DashboardView1().environmentObject(profile)
            } else {
                FormView {
                    InstallProfileButton()
                }
            }
        }
    }

    struct DashboardView1: View {
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?

        var body: some View {
            ActiveDashboardView()
                .environmentObject(profile)
            EmptyView()
                .alertBinding($alert)
                .onChangeCompat(of: profile.status) { newValue in
                    if newValue == .disconnecting || newValue == .connected {
                        Task.detached {
                            if let serviceError = try? String(contentsOf: ExtensionProvider.errorFile) {
                                DispatchQueue.main.async {
                                    alert = Alert(errorMessage: serviceError)
                                }
                                try? FileManager.default.removeItem(at: ExtensionProvider.errorFile)
                            }
                        }
                    }
                }
        }
    }
}
