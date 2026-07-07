import Combine
import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public struct AlertState: Equatable {
    public var title: String
    public var message: String
    public var primaryButton: ButtonState?
    public var secondaryButton: ButtonState?
    public var onDismiss: (() -> Void)?

    public struct ButtonState: Equatable {
        public var label: String
        public var role: ButtonRole?
        public var action: (() -> Void)?

        public init(label: String, role: ButtonRole? = nil, action: (() -> Void)? = nil) {
            self.label = label
            self.role = role
            self.action = action
        }

        public static func == (lhs: ButtonState, rhs: ButtonState) -> Bool {
            lhs.label == rhs.label && lhs.role == rhs.role
        }

        public static func `default`(_ label: String, action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, action: action)
        }

        public static func cancel(_ label: String = String(localized: "Cancel"), action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, role: .cancel, action: action)
        }

        public static func destructive(_ label: String, action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, role: .destructive, action: action)
        }
    }

    private static func formatErrorMessage(action: String, error: Error) -> String {
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionText = normalizedAction.isEmpty ? "complete operation" : normalizedAction
        if normalizedDescription.isEmpty {
            return "Failed to \(actionText)"
        }
        return "Failed to \(actionText)\n\(normalizedDescription)"
    }

    private static func copyErrorMessage(_ text: String) {
        #if canImport(UIKit) && !os(tvOS)
            UIPasteboard.general.string = text
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private static var supportsErrorCopy: Bool {
        #if canImport(UIKit) && !os(tvOS)
            true
        #elseif canImport(AppKit)
            true
        #else
            false
        #endif
    }

    public init(action: String, error: Error, dismiss: (() -> Void)? = nil) {
        let errorMessage = Self.formatErrorMessage(action: action, error: error)
        self.init(errorMessage: errorMessage, dismiss: dismiss)
        if Self.supportsErrorCopy {
            primaryButton = .default(String(localized: "Copy")) {
                Self.copyErrorMessage(errorMessage)
            }
            secondaryButton = .default(String(localized: "Ok"), action: dismiss)
        }
    }

    public init(errorMessage: String, dismiss: (() -> Void)? = nil) {
        title = String(localized: "Error")
        message = errorMessage
        if Self.supportsErrorCopy {
            primaryButton = .default(String(localized: "Copy")) {
                Self.copyErrorMessage(errorMessage)
            }
            secondaryButton = .default(String(localized: "Ok"), action: dismiss)
        } else {
            primaryButton = .default(String(localized: "Ok"), action: dismiss)
            secondaryButton = nil
        }
        onDismiss = nil
    }

    public init(title: String, message: String, dismissButton: ButtonState? = nil) {
        self.title = title
        self.message = message
        primaryButton = dismissButton ?? .default(String(localized: "Ok"))
        secondaryButton = nil
        onDismiss = nil
    }

    public init(title: String, message: String, primaryButton: ButtonState, secondaryButton: ButtonState) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        onDismiss = nil
    }

    public init(title: String, message: String, primaryButton: ButtonState, secondaryButton: ButtonState, onDismiss: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        self.onDismiss = onDismiss
    }

    public static func == (lhs: AlertState, rhs: AlertState) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message &&
            lhs.primaryButton == rhs.primaryButton && lhs.secondaryButton == rhs.secondaryButton
    }
}

public extension View {
    func alert(_ binding: Binding<AlertState?>) -> some View {
        alert(
            binding.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { binding.wrappedValue != nil },
                set: { newValue, _ in
                    if !newValue {
                        binding.wrappedValue?.onDismiss?()
                        binding.wrappedValue = nil
                    }
                }
            ),
            presenting: binding.wrappedValue
        ) { alertState in
            if let secondary = alertState.secondaryButton {
                Button(role: alertState.primaryButton?.role) {
                    alertState.primaryButton?.action?()
                } label: {
                    Text(alertState.primaryButton?.label ?? "Ok")
                }
                Button(role: secondary.role) {
                    secondary.action?()
                } label: {
                    Text(secondary.label)
                }
            } else if let primary = alertState.primaryButton {
                Button(role: primary.role) {
                    primary.action?()
                } label: {
                    Text(primary.label)
                }
            }
        } message: { alertState in
            Text(alertState.message)
        }
    }
}

public struct ImportRemoteProfileRequest: Hashable, Identifiable {
    public var id: String {
        url
    }

    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

@MainActor
public class ExtensionEnvironments: ObservableObject {
    @Published public var commandClient = CommandClient([.log, .status, .groups, .clashMode])
    public let crashReportManager = CrashReportManager()
    public let oomReportManager = OOMReportManager()
    public var totalUnreadReportCount: Int {
        crashReportManager.unreadCount + oomReportManager.unreadCount
    }

    @Published public var extensionProfileLoading = true
    @Published public var extensionProfile: ExtensionProfile?
    @Published public var emptyProfiles = false
    @Published public var pendingImportRemoteProfile: ImportRemoteProfileRequest?
    @Published public var remoteServer: RemoteServer?
    /// Set when a remote control session fails: the session is already torn down
    /// (back to local device), and the UI should surface this alert once.
    @Published public var remoteControlAlert: AlertState?
    private var remoteSessionHadConnected = false
    private var remoteSessionConnectedAt: Date?
    private var remoteReconnectAttempts = 0
    private var remoteReconnectPending = false
    #if canImport(UIKit)
        private var isInBackground = false
    #endif

    /// A dropped session gets this many silent reconnect attempts before the
    /// failure is surfaced. The counter resets once a connection survives
    /// `remoteStableConnectionInterval`, so only rapid connect-drop loops
    /// exhaust it.
    private static let maxRemoteReconnectAttempts = 3
    private static let remoteStableConnectionInterval: TimeInterval = 5

    public var logSearchText = ""
    public var connectionSearchText = ""

    public let profileUpdate = ObjectWillChangePublisher()
    public let selectedProfileUpdate = ObjectWillChangePublisher()
    public let openSettings = ObjectWillChangePublisher()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        crashReportManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        oomReportManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        commandClient.$isConnected
            .sink { [weak self] isConnected in
                guard isConnected else { return }
                Task { @MainActor [weak self] in
                    guard let self, remoteServer != nil else { return }
                    remoteSessionHadConnected = true
                    remoteSessionConnectedAt = Date()
                }
            }
            .store(in: &cancellables)
        commandClient.$lastError
            .sink { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    self?.handleRemoteControlError(error)
                }
            }
            .store(in: &cancellables)
        #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.isInBackground = true
                    }
                }
                .store(in: &cancellables)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleEnterForeground()
                    }
                }
                .store(in: &cancellables)
        #endif
        if Variant.screenshotMode {
            extensionProfileLoading = false
            extensionProfile = .mock
            commandClient.setupMockData()
        }
    }

    public func postReload() {
        Task {
            await restoreRemoteControl()
            await reload()
            await crashReportManager.refresh()
            await oomReportManager.refresh()
        }
    }

    private var remoteControlRestored = false
    private func restoreRemoteControl() async {
        // Remote control is not available on tvOS.
        #if !os(tvOS)
            if Variant.screenshotMode {
                return
            }
            guard !remoteControlRestored else { return }
            remoteControlRestored = true
            let serverID = await SharedPreferences.activeRemoteServerID.get()
            guard serverID != 0, remoteServer == nil else { return }
            guard let server = try? await RemoteServerManager.get(serverID) else {
                await SharedPreferences.activeRemoteServerID.set(0)
                return
            }
            enterRemoteControl(server)
        #endif
    }

    public func reload() async {
        if Variant.screenshotMode {
            return
        }
        if let newProfile = try? await ExtensionProfile.load() {
            if extensionProfile == nil || extensionProfile?.status == .invalid {
                newProfile.register()
                extensionProfile = newProfile
                extensionProfileLoading = false
            }
        } else {
            extensionProfile = nil
            extensionProfileLoading = false
        }
    }

    /// Whether a service daemon (local extension or remote server) is available
    /// for command client calls.
    public var serviceAvailable: Bool {
        if remoteServer != nil {
            return true
        }
        return extensionProfile?.status.isConnectedStrict == true
    }

    public func connect() {
        if Variant.screenshotMode {
            return
        }
        if remoteServer != nil {
            if !commandClient.isConnected {
                commandClient.connect()
            }
            return
        }
        guard let profile = extensionProfile else {
            return
        }
        if profile.status.isConnected, !commandClient.isConnected {
            commandClient.connect()
        }
    }

    public func enterRemoteControl(_ server: RemoteServer) {
        CommandTarget.setRemoteServer(server)
        remoteServer = server
        resetRemoteSessionState()
        commandClient.disconnect()
        commandClient.lastError = nil
        commandClient.connect()
        Task {
            await SharedPreferences.activeRemoteServerID.set(server.mustID)
        }
    }

    public func exitRemoteControl() {
        guard remoteServer != nil else {
            return
        }
        CommandTarget.setRemoteServer(nil)
        remoteServer = nil
        resetRemoteSessionState()
        commandClient.disconnect()
        commandClient.lastError = nil
        connect()
        Task {
            await SharedPreferences.activeRemoteServerID.set(0)
        }
    }

    private func resetRemoteSessionState() {
        remoteSessionHadConnected = false
        remoteSessionConnectedAt = nil
        remoteReconnectAttempts = 0
        remoteReconnectPending = false
    }

    #if canImport(UIKit)
        private func handleEnterForeground() {
            isInBackground = false
            // Recover the remote session on resume: a drop deferred while
            // backgrounded, or a connection iOS suspended (whose isConnected
            // flag may still read true against a now-dead socket). A suspension
            // is not a real failure, so the retry budget is restored.
            guard remoteServer != nil, remoteReconnectPending || !commandClient.isConnected else {
                return
            }
            remoteReconnectPending = false
            remoteReconnectAttempts = 0
            if commandClient.isConnected {
                commandClient.disconnect()
            }
            commandClient.connect()
        }
    #endif

    /// A remote session that cannot connect falls back to the local device
    /// immediately: leaving the app in remote mode would just make every
    /// command call fail at the point of use. A drop of an established session
    /// (app suspension, network change, server restart) is recoverable instead,
    /// so it reconnects silently and only surfaces the error once reconnecting
    /// fails too.
    private func handleRemoteControlError(_ error: CommandClient.ConnectionError) {
        guard let server = remoteServer, commandClient.lastError == error else {
            return
        }
        #if canImport(UIKit)
            if isInBackground {
                // A connection cannot be (re)established while iOS has the app
                // suspended, and an alert shown now would be invisible. Defer
                // recovery to the next foreground transition for any error,
                // without spending a retry attempt on a doomed connection.
                remoteSessionConnectedAt = nil
                remoteReconnectAttempts = 0
                remoteReconnectPending = true
                commandClient.lastError = nil
                return
            }
        #endif
        if error.kind == .connectionLost {
            if let connectedAt = remoteSessionConnectedAt,
               Date().timeIntervalSince(connectedAt) >= Self.remoteStableConnectionInterval
            {
                remoteReconnectAttempts = 0
            }
            remoteSessionConnectedAt = nil
            if remoteReconnectAttempts < Self.maxRemoteReconnectAttempts {
                remoteReconnectAttempts += 1
                commandClient.lastError = nil
                commandClient.connect()
                return
            }
        }
        // A non-retryable connect failure, or a dropped session whose retry
        // budget is spent: fall back to the local device, then surface the
        // failure once.
        let description = remoteSessionHadConnected
            ? "Disconnected from remote server \(server.displayName)"
            : "Failed to connect to remote server \(server.displayName)"
        exitRemoteControl()
        remoteControlAlert = AlertState(errorMessage: "\(description)\n\(error.message)")
    }
}
