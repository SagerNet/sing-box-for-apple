import Libbox
import Library
import NetworkExtension
import SwiftUI

@MainActor
class DashboardViewModel: ObservableObject {
    #if os(macOS)
        @Published var isLoading = true
        @Published var systemExtensionInstalled = true
    #endif

    @Published var alert: Alert?
    @Published var notStarted = false

    private var openURL: ((URL) -> Void)?

    func setOpenURL(_ openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
    }

    #if os(macOS)
        nonisolated func reload() async {
            let systemExtensionInstalled = await SystemExtension.isInstalled()
            await MainActor.run {
                self.systemExtensionInstalled = systemExtensionInstalled
                self.isLoading = false
            }
        }
    #endif

    func handleStatusChange(_ status: NEVPNStatus, profile: ExtensionProfile) {
        if status == .connected {
            notStarted = false
        }
        if status == .disconnecting || status == .connected {
            Task {
                await checkServiceError()
                if status == .connected {
                    await checkDeprecatedNotes()
                }
            }
        } else if status == .connecting {
            notStarted = true
        } else if status == .disconnected {
            if #available(iOS 16.0, macOS 13.0, tvOS 17.0, *) {
                if notStarted {
                    Task {
                        await checkLastDisconnectError(profile: profile)
                    }
                }
            }
        }
    }

    nonisolated func checkDeprecatedNotes() async {
        if await SharedPreferences.disableDeprecatedWarnings.get() {
            return
        }
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

    private func loopShowDeprecateNotes(_ reports: any LibboxDeprecatedNoteIteratorProtocol) {
        if reports.hasNext() {
            let report = reports.next()!
            if report.migrationLink.isEmpty {
                alert = Alert(
                    title: Text("Deprecated Warning"),
                    message: Text(report.message()),
                    dismissButton: .cancel(Text("Ok")) {
                        Task.detached { [weak self] in
                            try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                            await self?.loopShowDeprecateNotes(reports)
                        }
                    }
                )
            } else {
                alert = Alert(
                    title: Text("Deprecated Warning"),
                    message: Text(report.message()),
                    primaryButton: .default(Text("Documentation")) {
                        self.openURL?(URL(string: report.migrationLink)!)
                        Task.detached { [weak self] in
                            try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                            await self?.loopShowDeprecateNotes(reports)
                        }
                    },
                    secondaryButton: .cancel(Text("Ok")) {
                        Task.detached { [weak self] in
                            try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                            await self?.loopShowDeprecateNotes(reports)
                        }
                    }
                )
            }
        }
    }

    nonisolated func checkServiceError() async {
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
    nonisolated func checkLastDisconnectError(profile: ExtensionProfile) async {
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
                        message: Text("Please grant the permission for **SFMExtension**, then we can continue."),
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
