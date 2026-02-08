import Foundation
import Libbox
import Library
import NetworkExtension
import os
import SwiftUI

#if os(macOS)
    import AppKit
#endif

private let logger = Logger(category: "DashboardViewModel")

@MainActor
public final class DashboardViewModel: BaseViewModel {
    @Published public var profileList: [ProfilePreview] = []
    @Published public var selectedProfileID: Int64 = 0
    @Published public var systemProxyAvailable = false
    @Published public var systemProxyEnabled = false

    #if os(macOS)
        @Published public var systemExtensionInstalled = true
    #endif

    private weak var environments: ExtensionEnvironments?

    public func setEnvironments(_ environments: ExtensionEnvironments) {
        self.environments = environments
    }

    override public init() {
        super.init()
        isLoading = true
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

        if Variant.screenshotMode {
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
                    environments?.emptyProfiles = true
                    return
                }

                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if !profileList.contains(where: { $0.id == selectedProfileID }) {
                    selectedProfileID = profileList[0].id
                    await SharedPreferences.selectedProfileID.set(selectedProfileID)
                }
            } catch {
                alert = AlertState(action: "load profile list", error: error)
                return
            }
        }
        environments?.emptyProfiles = profileList.isEmpty
    }

    public func reloadSystemProxy() async {
        do {
            let status = try LibboxNewStandaloneCommandClient()!.getSystemProxyStatus()
            systemProxyAvailable = status.available
            systemProxyEnabled = status.enabled
        } catch {
            logger.debug("reloadSystemProxy: \(error)")
        }
    }

    public func updateSelectedProfile() async {
        selectedProfileID = await SharedPreferences.selectedProfileID.get()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
extension ExtensionProfile {
    public nonisolated func checkLastDisconnectError() async -> AlertState? {
        do {
            try await fetchLastDisconnectError()
            return nil
        } catch {
            let nsError = error as NSError
            #if os(macOS)
                if nsError.domain == "Library.FullDiskAccessPermissionRequired" {
                    return AlertState(
                        title: String(localized: "Full Disk Access permission is required"),
                        message: String(localized: "Please grant the permission for **SFMExtension**, then we can continue."),
                        primaryButton: .default(String(localized: "Authorize"), action: Self.openFDASettings),
                        secondaryButton: .cancel()
                    )
                }
            #endif
            return AlertState(action: "fetch last disconnect error", error: nsError)
        }
    }

    #if os(macOS)
        private static func openFDASettings() {
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
