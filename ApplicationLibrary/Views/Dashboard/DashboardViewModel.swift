import Foundation
import Libbox
import Library
import NetworkExtension
import SwiftUI

@MainActor
public final class DashboardViewModel: BaseViewModel {
    @Published public var profileList: [ProfilePreview] = []
    @Published public var selectedProfileID: Int64 = 0
    @Published public var selection = DashboardPage.overview
    @Published public var systemProxyAvailable = false
    @Published public var systemProxyEnabled = false
    @Published public var notStarted = false

    #if os(macOS)
        @Published public var systemExtensionInstalled = true
    #endif

    public var onEmptyProfilesChange: ((Bool) -> Void)?
    private var openURL: ((URL) -> Void)?

    override public init() {
        super.init()
        isLoading = true
    }

    public func setOpenURL(_ openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
    }

    public func reload() async {
        #if os(macOS)
            if Variant.useSystemExtension {
                let installed = await SystemExtension.isInstalled()
                systemExtensionInstalled = installed
                guard installed else {
                    isLoading = false
                    return
                }
            }
        #endif

        defer { isLoading = false }

        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
            systemProxyAvailable = true
            systemProxyEnabled = true
            selectedProfileID = 0
        } else {
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
                guard !profileList.isEmpty else {
                    onEmptyProfilesChange?(true)
                    return
                }

                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if !profileList.contains(where: { $0.id == selectedProfileID }) {
                    selectedProfileID = profileList[0].id
                    await SharedPreferences.selectedProfileID.set(selectedProfileID)
                }
            } catch {
                alert = AlertState(error: error)
                return
            }
        }
        onEmptyProfilesChange?(profileList.isEmpty)
    }

    public func reloadSystemProxy() async {
        do {
            let status = try LibboxNewStandaloneCommandClient()!.getSystemProxyStatus()
            systemProxyAvailable = status.available
            systemProxyEnabled = status.enabled
        } catch {
            alert = AlertState(error: error)
        }
    }

    public func updateSelectedProfile() async {
        selectedProfileID = await SharedPreferences.selectedProfileID.get()
    }

    public func handleStatusChange(_ status: NEVPNStatus, profile: ExtensionProfile) {
        if status == .connected {
            notStarted = false
            Task { await checkDeprecatedNotes() }
        } else if status == .connecting {
            notStarted = true
        } else if status == .disconnected {
            if #available(iOS 16.0, macOS 13.0, tvOS 17.0, *) {
                if notStarted {
                    Task { await checkLastDisconnectError(profile: profile) }
                }
            }
        }
    }

    nonisolated func checkDeprecatedNotes() async {
        let disableWarnings = await SharedPreferences.disableDeprecatedWarnings.get()
        guard !disableWarnings else { return }

        do {
            let reports = try LibboxNewStandaloneCommandClient()!.getDeprecatedNotes()
            if reports.hasNext() {
                await MainActor.run {
                    loopShowDeprecateNotes(reports)
                }
            }
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }

    private func loopShowDeprecateNotes(_ reports: any LibboxDeprecatedNoteIteratorProtocol) {
        guard reports.hasNext() else { return }

        let report = reports.next()!
        let continueChain: () -> Void = { [weak self] in
            _ = Task.detached {
                try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                await self?.loopShowDeprecateNotes(reports)
            }
        }

        if report.migrationLink.isEmpty {
            alert = AlertState(
                title: String(localized: "Deprecated Warning"),
                message: report.message(),
                dismissButton: .cancel(String(localized: "Ok"))
            )
            alert?.onDismiss = continueChain
        } else {
            alert = AlertState(
                title: String(localized: "Deprecated Warning"),
                message: report.message(),
                primaryButton: .default(String(localized: "Documentation")) {
                    self.openURL?(URL(string: report.migrationLink)!)
                },
                secondaryButton: .cancel(String(localized: "Ok")),
                onDismiss: continueChain
            )
        }
    }

    @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
    nonisolated func checkLastDisconnectError(profile: ExtensionProfile) async {
        do {
            try await profile.fetchLastDisconnectError()
            return
        } catch {
            let myError = error as NSError
            #if os(macOS)
                if myError.domain == "Library.FullDiskAccessPermissionRequired" {
                    await MainActor.run {
                        alert = AlertState(
                            title: String(localized: "Full Disk Access permission is required"),
                            message: String(localized: "Please grant the permission for **SFMExtension**, then we can continue."),
                            primaryButton: .default(String(localized: "Authorize"), action: openFDASettings),
                            secondaryButton: .cancel()
                        )
                    }
                    return
                }
            #endif
            await MainActor.run {
                alert = AlertState(title: String(localized: "Service Error"), message: myError.localizedDescription)
            }
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
