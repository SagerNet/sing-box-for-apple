#if os(macOS)
    import Library
    import SwiftUI

    private struct NewTerminalWindowActionKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    private struct OpenTerminalWindowActionKey: FocusedValueKey {
        typealias Value = (TailscaleSSHPresentedSession) -> Void
    }

    private struct CurrentTerminalSessionKey: FocusedValueKey {
        typealias Value = TailscaleSSHPresentedSession
    }

    private struct QuickConnectPeersKey: FocusedValueKey {
        typealias Value = [TailscaleSSHPeerEntry]
    }

    extension FocusedValues {
        var newTerminalWindowAction: (() -> Void)? {
            get { self[NewTerminalWindowActionKey.self] }
            set { self[NewTerminalWindowActionKey.self] = newValue }
        }

        var openTerminalWindowAction: ((TailscaleSSHPresentedSession) -> Void)? {
            get { self[OpenTerminalWindowActionKey.self] }
            set { self[OpenTerminalWindowActionKey.self] = newValue }
        }

        var currentTerminalSession: TailscaleSSHPresentedSession? {
            get { self[CurrentTerminalSessionKey.self] }
            set { self[CurrentTerminalSessionKey.self] = newValue }
        }

        var quickConnectPeers: [TailscaleSSHPeerEntry]? {
            get { self[QuickConnectPeersKey.self] }
            set { self[QuickConnectPeersKey.self] = newValue }
        }
    }

    public struct TerminalCommands: Commands {
        @FocusedValue(\.newTerminalWindowAction) var newWindowAction
        @FocusedValue(\.openTerminalWindowAction) var openTerminalWindowAction
        @FocusedValue(\.currentTerminalSession) var currentSession
        @FocusedValue(\.quickConnectPeers) var quickConnectPeers

        private var otherQCPeers: [TailscaleSSHPeerEntry] {
            (quickConnectPeers ?? []).filter { peer in
                guard let current = currentSession else { return true }
                return !(peer.endpointTag == current.endpointTag && peer.peerAddress == current.peerAddress)
            }
        }

        public init() {}

        public var body: some Commands {
            if let newWindowAction {
                CommandGroup(replacing: .newItem) {
                    if otherQCPeers.isEmpty {
                        Button {
                            newWindowAction()
                        } label: {
                            Label("New Window", systemImage: "macwindow.badge.plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                    } else {
                        Menu {
                            Button {
                                newWindowAction()
                            } label: {
                                Label(currentSession?.peerDisplayName ?? String(localized: "New Window"), systemImage: "doc.on.doc")
                            }
                            .keyboardShortcut("n", modifiers: .command)

                            Divider()

                            ForEach(otherQCPeers) { peer in
                                Button {
                                    guard let openAction = openTerminalWindowAction else { return }
                                    Task { @MainActor in
                                        let session = await peer.createSession()
                                        openAction(session)
                                    }
                                } label: {
                                    Label(peer.displayName, systemImage: "terminal")
                                }
                            }
                        } label: {
                            Label("New Window", systemImage: "macwindow.badge.plus")
                        }
                    }
                }
            }
        }
    }
#endif
