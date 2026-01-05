import Libbox
import Library
import NetworkExtension
import SwiftUI
#if os(macOS)
    import CoreLocation
#endif

#if os(macOS)
    @MainActor
    private final class WIFIStateLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        var onAuthorizationGranted: (() -> Void)?
        private var pendingAuthorizationRequest = false

        override init() {
            super.init()
            manager.delegate = self
        }

        func requestAuthorizationAndShowWarning() {
            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                pendingAuthorizationRequest = true
                manager.requestAlwaysAuthorization()
            default:
                break
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            Task { @MainActor in
                guard self.pendingAuthorizationRequest else { return }
                self.pendingAuthorizationRequest = false
                let status = manager.authorizationStatus
                if status == .authorized || status == .authorizedAlways {
                    self.onAuthorizationGranted?()
                }
            }
        }
    }
#endif

@MainActor
public struct GlobalChecksModifier: ViewModifier {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.importProfile) private var importProfile
    @Environment(\.importRemoteProfile) private var importRemoteProfile
    @Environment(\.selection) private var selection

    @State private var alert: AlertState?
    @State private var notStarted = false
    @Environment(\.openURL) private var openURL

    #if os(macOS)
        @StateObject private var wifiLocationManager = WIFIStateLocationManager()
    #endif

    public init() {}

    public func body(content: Content) -> some View {
        contentView(content)
            .alert($alert)
            .onAppear {
                handleImportProfile()
                handleImportRemoteProfile()
            }
            .onChangeCompat(of: importProfile.wrappedValue) { _ in
                Task { @MainActor in handleImportProfile() }
            }
            .onChangeCompat(of: importRemoteProfile.wrappedValue) { _ in
                Task { @MainActor in handleImportRemoteProfile() }
            }
            .onChangeCompat(of: environments.extensionProfile?.status) { status in
                handleStatusChange(status)
            }
    }

    @ViewBuilder
    private func contentView(_ content: Content) -> some View {
        #if os(macOS)
            content
                .onReceive(NotificationCenter.default.publisher(for: .extensionRequiresWIFIState)) { _ in
                    Task { @MainActor in handleWiFiStateNotification() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .extensionRequiresHelperService)) { _ in
                    Task { @MainActor in handleHelperServiceNotification() }
                }
        #else
            content
        #endif
    }

    private func handleImportProfile() {
        guard let profile = importProfile.wrappedValue else { return }
        importProfile.wrappedValue = nil
        alert = AlertState(
            title: String(localized: "Import Profile"),
            message: String(localized: "Are you sure to import profile \(profile.name)?"),
            primaryButton: .default(String(localized: "Import")) { [weak environments, selection] in
                selection.wrappedValue = .dashboard
                Task {
                    do {
                        try await profile.importProfile()
                    } catch {
                        await MainActor.run {
                            alert = AlertState(error: error)
                        }
                        return
                    }
                    environments?.profileUpdate.send()
                }
            },
            secondaryButton: .cancel()
        )
    }

    private func handleImportRemoteProfile() {
        guard let remoteProfile = importRemoteProfile.wrappedValue else { return }
        importRemoteProfile.wrappedValue = nil
        alert = AlertState(
            title: String(localized: "Import Remote Profile"),
            message: String(localized: "Are you sure to import remote profile \(remoteProfile.name)? You will connect to \(remoteProfile.host) to download the configuration."),
            primaryButton: .default(String(localized: "Import")) { [weak environments, selection] in
                selection.wrappedValue = .dashboard
                environments?.pendingImportRemoteProfile = ImportRemoteProfileRequest(name: remoteProfile.name, url: remoteProfile.url)
            },
            secondaryButton: .cancel()
        )
    }

    private func handleStatusChange(_ status: NEVPNStatus?) {
        Task { @MainActor in
            guard let status else { return }
            switch status {
            case .connected:
                notStarted = false
                await checkDeprecatedNotes()
            case .connecting:
                notStarted = true
            case .disconnected:
                if #available(iOS 16.0, macOS 13.0, tvOS 17.0, *) {
                    if notStarted, let profile = environments.extensionProfile {
                        await checkLastDisconnectError(profile: profile)
                    }
                }
                notStarted = false
            default:
                break
            }
        }
    }

    @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
    private nonisolated func checkLastDisconnectError(profile: ExtensionProfile) async {
        if let alertState = await profile.checkLastDisconnectError() {
            await MainActor.run {
                alert = alertState
            }
        }
    }

    private nonisolated func checkDeprecatedNotes() async {
        let disableWarnings = await SharedPreferences.disableDeprecatedWarnings.get()
        guard !disableWarnings else { return }

        do {
            let reports = try LibboxNewStandaloneCommandClient()!.getDeprecatedNotes()
            if reports.hasNext() {
                await MainActor.run {
                    showNextDeprecatedNote(reports)
                }
            }
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }

    private func showNextDeprecatedNote(_ reports: any LibboxDeprecatedNoteIteratorProtocol) {
        guard reports.hasNext() else { return }

        let report = reports.next()!
        let continueChain: () -> Void = {
            Task.detached {
                try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                await MainActor.run {
                    showNextDeprecatedNote(reports)
                }
            }
        }

        if report.migrationLink.isEmpty {
            var state = AlertState(
                title: String(localized: "Deprecated Warning"),
                message: report.message(),
                dismissButton: .cancel(String(localized: "Ok"))
            )
            state.onDismiss = continueChain
            alert = state
        } else {
            alert = AlertState(
                title: String(localized: "Deprecated Warning"),
                message: report.message(),
                primaryButton: .default(String(localized: "Documentation")) {
                    openURL(URL(string: report.migrationLink)!)
                },
                secondaryButton: .cancel(String(localized: "Ok")),
                onDismiss: continueChain
            )
        }
    }

    #if os(macOS)
        private func handleWiFiStateNotification() {
            guard Variant.useSystemExtension else { return }
            wifiLocationManager.onAuthorizationGranted = {
                alert = AlertState(
                    title: String(localized: "WiFi State Access"),
                    message: String(localized: "In the standalone version of SFM, reading WiFi state requires this app to be running. After you quit the SFM app, the sing-box service cannot continue to provide `wifi_ssid` and `wifi_bssid` routing rules.")
                )
            }
            wifiLocationManager.requestAuthorizationAndShowWarning()
        }

        private func handleHelperServiceNotification() {
            guard Variant.useSystemExtension, HelperServiceManager.rootHelperStatus != .enabled else { return }
            alert = AlertState(
                title: String(localized: "Helper Service Required"),
                message: String(localized: "The sing-box service requires Helper Service to provide process lookup functionality, which supports `process_name` and `process_path` routing rules."),
                primaryButton: .default(String(localized: "App Settings")) {
                    NotificationCenter.default.post(name: .navigateToSettingsPage, object: SettingsPage.app)
                },
                secondaryButton: .cancel()
            )
        }
    #endif
}

public extension View {
    func globalChecks() -> some View {
        modifier(GlobalChecksModifier())
    }
}
