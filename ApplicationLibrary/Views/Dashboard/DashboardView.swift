import Libbox
import Library
import SwiftUI

@MainActor
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
                                InstallSystemExtensionButton {
                                    await reload()
                                }
                            }
                        } else {
                            DashboardView0()
                        }
                    }.onAppear {
                        Task {
                            await reload()
                        }
                    }
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
                        Task {
                            await reload()
                        }
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
        private nonisolated func reload() async {
            let systemExtensionInstalled = await SystemExtension.isInstalled()
            await MainActor.run {
                self.systemExtensionInstalled = systemExtensionInstalled
                isLoading = false
            }
        }
    #endif

    struct DashboardView0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments

        var body: some View {
            if ApplicationLibrary.inPreview {
                ActiveDashboardView()
            } else if environments.extensionProfileLoading {
                ProgressView()
            } else if let profile = environments.extensionProfile {
                DashboardView1().environmentObject(profile)
            } else {
                FormView {
                    InstallProfileButton {
                        await environments.reload()
                    }
                }
            }
        }
    }

    struct DashboardView1: View {
        @Environment(\.openURL) var openURL
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?
        @State private var notStarted = false

        var body: some View {
            VStack {
                ActiveDashboardView()
            }
            .alertBinding($alert)
            .onChangeCompat(of: profile.status) { newValue in
                if newValue == .connected {
                    notStarted = false
                }
                if newValue == .disconnecting || newValue == .connected {
                    Task {
                        await checkServiceError()
                        if newValue == .connected {
                            await checkDeprecatedNotes()
                        }
                    }
                } else if newValue == .connecting {
                    notStarted = true
                } else if newValue == .disconnected {
                    if #available(iOS 16.0, macOS 13.0, tvOS 17.0, *) {
                        if notStarted {
                            Task {
                                await checkLastDisconnectError()
                            }
                        }
                    }
                }
            }
        }

        private nonisolated func checkDeprecatedNotes() async {
            do {
                let reports = try LibboxNewStandaloneCommandClient()!.getDeprecatedNotes()
                if reports.hasNext() {
                    await MainActor.run {
                        loopShowDeprecateNotes(reports)
                    }
                }
            } catch {
                await MainActor.run {
                    alert = Alert(error)
                }
            }
        }

        @MainActor
        private func loopShowDeprecateNotes(_ reports: any LibboxDeprecatedNoteIteratorProtocol) {
            if reports.hasNext() {
                let report = reports.next()!
                alert = Alert(
                    title: Text("Deprecated Warning"),
                    message: Text(report.message()),
                    primaryButton: .default(Text("Documentation")) {
                        openURL(URL(string: report.migrationLink)!)
                        Task.detached {
                            try await Task.sleep(nanoseconds: 300 * MSEC_PER_SEC)
                            await loopShowDeprecateNotes(reports)
                        }
                    },
                    secondaryButton: .cancel(Text("Ok")) {
                        Task.detached {
                            try await Task.sleep(nanoseconds: 300 * MSEC_PER_SEC)
                            await loopShowDeprecateNotes(reports)
                        }
                    }
                )
            }
        }

        private nonisolated func checkServiceError() async {
            var error: NSError?
            let message = LibboxReadServiceError(&error)
            if error != nil {
                return
            }
            await MainActor.run {
                alert = Alert(title: Text("Service Error"), message: Text(message!.value))
            }
        }

        @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
        private nonisolated func checkLastDisconnectError() async {
            var myError: NSError
            do {
                try await profile.fetchLastDisconnectError()
                return
            } catch {
                myError = error as NSError
            }
            #if os(macOS)
                if myError.domain == "Library.FullDiskAccessPermissionRequired" {
                    await MainActor.run {
                        alert = Alert(
                            title: Text("Full Disk Access permission is required"),
                            message: Text("Please grant the permission for SFMExtension, then we can continue."),
                            primaryButton: .default(Text("Authorize"), action: openFDASettings),
                            secondaryButton: .cancel()
                        )
                    }
                    return
                }
            #endif
            let message = myError.localizedDescription
            await MainActor.run {
                alert = Alert(title: Text("Service Error"), message: Text(message))
            }
        }

        #if os(macOS)

            private func openFDASettings() {
                if NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) {
                    return
                }
                if #available(macOS 13, *) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
                }
            }

        #endif
    }
}
