#if canImport(GhosttyTerminal)
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

    @MainActor
    public final class TerminalWrapperViewModel: ObservableObject {
        public enum Phase: Equatable {
            case connecting
            case running
            case finished(reason: TailscaleSSHEndReason)
        }

        @Published public private(set) var phase: Phase = .connecting
        @Published public private(set) var authBanner: String?

        @Published public private(set) var terminalState: TerminalViewState?
        public let extras = TailsshTerminalExtras()
        public var onWindowClose: (() -> Void)?
        private let terminalSession: InMemoryTerminalSession
        private let relay: TerminalRelay
        private var commandClient: LibboxCommandClient?
        private var libboxSession: LibboxTailscaleSSHSession?
        private var hasStarted = false
        private var isDisconnected = false
        private var inputContinuation: AsyncStream<Data>.Continuation?
        private var resizeContinuation: AsyncStream<TerminalResize>.Continuation?
        private var inputTask: Task<Void, Never>?
        private var resizeTask: Task<Void, Never>?
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
            self.relay = relay
            terminalSession = session
            relay.viewModel = self
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

        public func start(_ presentedSession: TailscaleSSHPresentedSession) async {
            guard !hasStarted, !isDisconnected, !Task.isCancelled else { return }
            hasStarted = true

            let lightTheme = await SharedPreferences.tailscaleSSHGhosttyLightTheme.get()
            let lightConfig = await SharedPreferences.tailscaleSSHGhosttyLightConfig.get()
            let darkTheme = await SharedPreferences.tailscaleSSHGhosttyDarkTheme.get()
            let darkConfig = await SharedPreferences.tailscaleSSHGhosttyDarkConfig.get()
            let fontOverlay = await Self.resolveFontOverlay()
            guard !isDisconnected, !Task.isCancelled else { return }

            let inputs = AsyncStream<Data> { inputContinuation = $0 }
            let resizes = AsyncStream<TerminalResize>(bufferingPolicy: .bufferingNewest(1)) {
                resizeContinuation = $0
            }
            let state = TerminalViewState(
                configSource: .none,
                theme: TerminalTheme(
                    light: Self.resolveConfiguration(themeName: lightTheme, customText: lightConfig, fallback: .alabaster),
                    dark: Self.resolveConfiguration(themeName: darkTheme, customText: darkConfig, fallback: .afterglow)
                ),
                terminalConfiguration: fontOverlay
            )
            state.configuration = TerminalSurfaceOptions(backend: .inMemory(terminalSession))
            extras.state = state
            terminalState = state

            let options = LibboxTailscaleSSHOptions()
            options.endpointTag = presentedSession.endpointTag
            options.peerAddress = presentedSession.peerAddress
            options.username = presentedSession.username
            options.terminalType = presentedSession.terminalType
            options.columns = 80
            options.rows = 24

            options.hostKeys = presentedSession.hostKeys.toStringIterator()
            options.forwardAgent = presentedSession.forwardAgent

            let handler = SessionHandler(self)
            do {
                let client = try CommandTarget.ownedStandaloneClient()
                commandClient = client
                let session = try await withTaskCancellationHandler {
                    try await BlockingIO.run {
                        try client.startTailscaleSSHSession(options, handler: handler)
                    }
                } onCancel: {
                    Task {
                        await BlockingIO.run { try? client.disconnect() }
                    }
                }
                libboxSession = session
                guard !isDisconnected, !Task.isCancelled else {
                    await disconnect()
                    return
                }
                if case .finished = phase {
                    await disconnect()
                    return
                }
                inputTask = Task {
                    for await data in inputs {
                        guard !Task.isCancelled else { return }
                        do {
                            try await BlockingIO.run {
                                let sanitized = Self.sanitizeTerminalInput(data)
                                if !sanitized.isEmpty {
                                    try session.sendInput(sanitized)
                                }
                            }
                        } catch {
                            return
                        }
                    }
                }
                resizeTask = Task {
                    for await resize in resizes {
                        guard !Task.isCancelled else { return }
                        do {
                            try await BlockingIO.run {
                                try session.sendResize(
                                    resize.columns,
                                    rows: resize.rows,
                                    widthPixels: resize.widthPixels,
                                    heightPixels: resize.heightPixels
                                )
                            }
                        } catch {
                            return
                        }
                    }
                }
            } catch {
                if !isDisconnected, !Task.isCancelled {
                    phase = .finished(reason: .error(error.localizedDescription))
                }
                await disconnect()
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

        private static func resolveFontOverlay() async -> TerminalConfiguration {
            let size = await SharedPreferences.tailscaleSSHTerminalFontSize.get()
            let followTheme = await SharedPreferences.tailscaleSSHTerminalFontFollowTheme.get()
            guard !followTheme else {
                return TerminalConfiguration { builder in
                    builder.withFontSize(Float(size))
                }
            }
            let family = await SharedPreferences.tailscaleSSHTerminalFontFamily.get()
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
                    if line.isEmpty || line.hasPrefix("#") {
                        continue
                    }
                    guard let eq = line.firstIndex(of: "=") else { continue }
                    let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                    let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty else { continue }
                    builder.withCustom(key, value)
                }
            }
        }

        public func disconnect() async {
            isDisconnected = true
            inputContinuation?.finish()
            resizeContinuation?.finish()
            inputContinuation = nil
            resizeContinuation = nil
            inputTask?.cancel()
            resizeTask?.cancel()
            inputTask = nil
            resizeTask = nil
            let session = libboxSession
            let client = commandClient
            libboxSession = nil
            commandClient = nil
            await BlockingIO.run {
                try? client?.disconnect()
                try? session?.close()
            }
        }

        fileprivate func handleTerminalWrite(_ data: Data) {
            inputContinuation?.yield(data)
        }

        private nonisolated static func sanitizeTerminalInput(_ data: Data) -> Data {
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
            resizeContinuation?.yield(TerminalResize(
                columns: Int32(viewport.columns),
                rows: Int32(viewport.rows),
                widthPixels: Int32(viewport.widthPixels),
                heightPixels: Int32(viewport.heightPixels)
            ))
        }

        private struct TerminalResize: Sendable {
            let columns: Int32
            let rows: Int32
            let widthPixels: Int32
            let heightPixels: Int32
        }

        fileprivate func didReceiveExit(exitCode: Int32, signal: String, message: String) {
            guard !isDisconnected else { return }
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
            if reason == .cleanExit {
                onWindowClose?()
            }
            Task { await disconnect() }
        }

        fileprivate func appendAuthBanner(_ message: String) {
            guard !isDisconnected else { return }
            let banner = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !banner.isEmpty else { return }
            guard let existingBanner = authBanner, !existingBanner.isEmpty else {
                authBanner = banner
                return
            }
            guard !existingBanner.contains(banner) else { return }
            authBanner = existingBanner + "\n\n" + banner
        }

        fileprivate func didReceiveError(_ message: String) {
            guard !isDisconnected else { return }
            if case .finished = phase {
                return
            }
            phase = .finished(reason: .error(message))
            Task { await disconnect() }
        }

        private final class SessionHandler: NSObject, LibboxTailscaleSSHHandlerProtocol, @unchecked Sendable {
            private weak var viewModel: TerminalWrapperViewModel?

            init(_ viewModel: TerminalWrapperViewModel?) {
                self.viewModel = viewModel
            }

            func onReady() {
                DispatchQueue.main.async { [self] in
                    guard let viewModel, !viewModel.isDisconnected else { return }
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
                    viewModel?.appendAuthBanner(banner)
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
            guard !isDisconnected else { return }
            terminalSession.receive(data)
        }
    }

    private final class TerminalRelay: @unchecked Sendable {
        weak var viewModel: TerminalWrapperViewModel?
    }
#endif
