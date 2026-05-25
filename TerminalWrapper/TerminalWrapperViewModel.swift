import Combine
import Foundation
import GhosttyTerminal
import GhosttyTheme
import Libbox
import Library
import SwiftUI
import UserNotifications

public enum TailscaleSSHEndReason: Equatable {
    case cleanExit
    case exitWithCode(Int32, signal: String?)
    case error(String)

    public var displayText: String {
        switch self {
        case .cleanExit:
            return "Session ended."
        case let .exitWithCode(code, .none):
            return "Session ended (exit \(code))."
        case let .exitWithCode(code, .some(signal)):
            return "Session ended (exit \(code), signal \(signal))."
        case let .error(message):
            return "Connection failed: \(message)"
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class TerminalWrapperViewModel: ObservableObject {
    public enum Phase: Equatable {
        case connecting
        case running
        case finished(reason: TailscaleSSHEndReason)
    }

    @Published public private(set) var phase: Phase = .connecting
    @Published public private(set) var authBanner: String?

    public let terminalState: TerminalViewState
    public let extras = TailsshTerminalExtras()
    public var onWindowClose: (() -> Void)?
    private let terminalSession: InMemoryTerminalSession
    private let relay: TerminalRelay
    private var commandClient: LibboxCommandClient?
    private var libboxSession: LibboxTailscaleSSHSession?
    private var hasStarted = false
    private let startedAt = Date()
    private var notificationAuthorizationRequested = false
    private var extrasCancellable: AnyCancellable?

    public init() {
        let relay = TerminalRelay()
        let session = InMemoryTerminalSession(
            write: { [weak relay] data in
                DispatchQueue.main.async {
                    relay?.viewModel?.handleTerminalWrite(data)
                }
            },
            resize: { [weak relay] viewport in
                DispatchQueue.main.async {
                    relay?.viewModel?.handleTerminalResize(viewport)
                }
            }
        )
        let theme = TerminalTheme(
            light: Self.resolveConfiguration(
                themeName: SharedPreferences.tailscaleSSHGhosttyLightTheme.getBlocking(),
                customText: SharedPreferences.tailscaleSSHGhosttyLightConfig.getBlocking(),
                fallback: .alabaster
            ),
            dark: Self.resolveConfiguration(
                themeName: SharedPreferences.tailscaleSSHGhosttyDarkTheme.getBlocking(),
                customText: SharedPreferences.tailscaleSSHGhosttyDarkConfig.getBlocking(),
                fallback: .afterglow
            )
        )
        let state = TerminalViewState(
            configSource: .none,
            theme: theme,
            terminalConfiguration: Self.resolveFontOverlay()
        )
        state.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        self.relay = relay
        terminalSession = session
        terminalState = state
        relay.viewModel = self
        extras.state = state
        extras.onClose = { [weak self] _ in
            self?.onWindowClose?()
        }
        extras.onDesktopNotification = { [weak self] title, body in
            self?.postSystemNotification(title: title, body: body)
        }
        extrasCancellable = extras.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func postSystemNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let deliver = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
        if notificationAuthorizationRequested {
            deliver()
            return
        }
        notificationAuthorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { deliver() }
        }
    }

    public func start(_ presentedSession: TailscaleSSHPresentedSession) {
        guard !hasStarted else { return }
        hasStarted = true

        let options = LibboxTailscaleSSHOptions()
        options.endpointTag = presentedSession.endpointTag
        options.peerAddress = presentedSession.peerAddress
        options.username = presentedSession.username
        options.terminalType = presentedSession.terminalType
        options.columns = 80
        options.rows = 24

        options.hostKeys = presentedSession.hostKeys.toStringIterator()

        let client = LibboxNewStandaloneCommandClient()!
        commandClient = client
        let handler = SessionHandler(self)
        do {
            libboxSession = try client.startTailscaleSSHSession(options, handler: handler)
        } catch {
            phase = .finished(reason: .error(error.localizedDescription))
            cleanupCommandClient()
        }
    }

    private static func resolveConfiguration(
        themeName: String,
        customText: String,
        fallback: TerminalConfiguration
    ) -> TerminalConfiguration {
        if themeName.isEmpty {
            return parseCustomConfig(customText)
        }
        return GhosttyThemeCatalog.theme(named: themeName)?.toTerminalConfiguration() ?? fallback
    }

    private static func resolveFontOverlay() -> TerminalConfiguration {
        let size = SharedPreferences.tailscaleSSHTerminalFontSize.getBlocking()
        guard !SharedPreferences.tailscaleSSHTerminalFontFollowTheme.getBlocking() else {
            return TerminalConfiguration { builder in
                builder.withFontSize(Float(size))
            }
        }
        let family = SharedPreferences.tailscaleSSHTerminalFontFamily.getBlocking()
        return TerminalConfiguration { builder in
            if !family.isEmpty {
                builder.withFontFamily(family)
            }
            builder.withFontSize(Float(size))
        }
    }

    private static func parseCustomConfig(_ text: String) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                builder.withCustom(key, value)
            }
        }
    }

    public func disconnect() {
        guard libboxSession != nil || commandClient != nil else { return }
        try? libboxSession?.close()
        libboxSession = nil
        cleanupCommandClient()
    }

    private func cleanupCommandClient() {
        try? commandClient?.disconnect()
        commandClient = nil
    }

    fileprivate func handleTerminalWrite(_ data: Data) {
        guard let session = libboxSession else { return }
        let sanitized = Self.sanitizeTerminalInput(data)
        guard !sanitized.isEmpty else { return }
        try? session.sendInput(sanitized)
    }

    /// libghostty wraps every soft-keyboard insertText in bracketed paste
    /// markers (ESC [ 2 0 0 ~ ... ESC [ 2 0 1 ~), which makes the remote shell
    /// treat each keystroke as paste content rather than a key press — Enter
    /// never triggers execute. Strip the markers and convert iOS-style LF to
    /// the CR that real terminals send for the Return key.
    private static func sanitizeTerminalInput(_ data: Data) -> Data {
        let startMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
        let endMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
        let input = Array(data)
        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        var index = 0
        while index < input.count {
            if input.suffix(from: index).starts(with: startMarker) {
                index += startMarker.count
                continue
            }
            if input.suffix(from: index).starts(with: endMarker) {
                index += endMarker.count
                continue
            }
            let byte = input[index]
            output.append(byte == 0x0A ? 0x0D : byte)
            index += 1
        }
        return Data(output)
    }

    fileprivate func handleTerminalResize(_ viewport: InMemoryTerminalViewport) {
        guard let session = libboxSession else { return }
        try? session.sendResize(
            Int32(viewport.columns),
            rows: Int32(viewport.rows),
            widthPixels: Int32(viewport.widthPixels),
            heightPixels: Int32(viewport.heightPixels)
        )
    }

    fileprivate func didReceiveExit(exitCode: Int32, signal: String, message: String) {
        let runtimeMs = UInt64(max(0, Date().timeIntervalSince(startedAt)) * 1000)
        terminalSession.finish(exitCode: UInt32(max(0, exitCode)), runtimeMilliseconds: runtimeMs)
        let reason: TailscaleSSHEndReason
        if !message.isEmpty {
            reason = .error(message)
        } else if exitCode == 0, signal.isEmpty {
            reason = .cleanExit
        } else {
            reason = .exitWithCode(exitCode, signal: signal.isEmpty ? nil : signal)
        }
        phase = .finished(reason: reason)
        cleanupCommandClient()
    }

    fileprivate func didReceiveError(_ message: String) {
        if case .finished = phase { return }
        phase = .finished(reason: .error(message))
        cleanupCommandClient()
    }

    private final class SessionHandler: NSObject, LibboxTailscaleSSHHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: TerminalWrapperViewModel?

        init(_ viewModel: TerminalWrapperViewModel?) {
            self.viewModel = viewModel
        }

        func onReady() {
            DispatchQueue.main.async { [self] in
                guard let viewModel else { return }
                if case .connecting = viewModel.phase {
                    viewModel.phase = .running
                }
                viewModel.authBanner = nil
            }
        }

        func onOutput(_ data: Data?) {
            guard let data, !data.isEmpty else { return }
            DispatchQueue.main.async { [self] in
                viewModel?.handleOutput(data)
            }
        }

        func onAuthBanner(_ message: String?) {
            let banner = message ?? ""
            DispatchQueue.main.async { [self] in
                viewModel?.authBanner = banner
            }
        }

        func onExit(_ exitCode: Int32, signal: String?, errorMessage: String?) {
            let signal = signal ?? ""
            let errorMessage = errorMessage ?? ""
            DispatchQueue.main.async { [self] in
                viewModel?.didReceiveExit(exitCode: exitCode, signal: signal, message: errorMessage)
            }
        }

        func onError(_ message: String?) {
            let message = message ?? ""
            DispatchQueue.main.async { [self] in
                viewModel?.didReceiveError(message)
            }
        }
    }

    fileprivate func handleOutput(_ data: Data) {
        terminalSession.receive(data)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private final class TerminalRelay: @unchecked Sendable {
    weak var viewModel: TerminalWrapperViewModel?
}
