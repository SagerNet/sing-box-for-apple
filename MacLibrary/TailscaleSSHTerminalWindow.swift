import AppKit
import ApplicationLibrary
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

struct TerminalCommands: Commands {
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

    var body: some Commands {
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
                            Label(currentSession?.peerHostName ?? String(localized: "New Window"), systemImage: "doc.on.doc")
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
                                Label(peer.hostName, systemImage: "terminal")
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

struct TailscaleSSHTerminalWindow: View {
    let session: TailscaleSSHPresentedSession?

    @EnvironmentObject private var peerStore: TailscaleSSHPeerStore
    @Environment(\.openWindow) private var openWindow
    @State private var hostWindow: NSWindow?
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if let session {
                TerminalWrapperView(session)
                    .focusedSceneValue(\.newTerminalWindowAction) { [openWindow] in
                        openWindow(value: TailscaleSSHPresentedSession(
                            endpointTag: session.endpointTag,
                            peerHostName: session.peerHostName,
                            peerAddress: session.peerAddress,
                            username: session.username,
                            terminalType: session.terminalType,
                            hostKeys: session.hostKeys,
                            forwardAgent: session.forwardAgent
                        ))
                    }
                    .focusedSceneValue(\.openTerminalWindowAction) { [openWindow] newSession in
                        openWindow(value: newSession)
                    }
                    .focusedSceneValue(\.currentTerminalSession, session)
                    .focusedSceneValue(\.quickConnectPeers, peerStore.quickConnectPeers)
            } else {
                Color.clear
            }
        }
        .background(WindowAccessor(callback: { window in
            hostWindow = window
        }))
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let host = hostWindow, event.window === host else { return event }
        let bareMods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard bareMods == [.command] else { return event }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n":
            guard let session else { return event }
            openWindow(value: TailscaleSSHPresentedSession(
                endpointTag: session.endpointTag,
                peerHostName: session.peerHostName,
                peerAddress: session.peerAddress,
                username: session.username,
                terminalType: session.terminalType,
                hostKeys: session.hostKeys,
                forwardAgent: session.forwardAgent
            ))
            return nil
        case "q":
            host.close()
            return nil
        default:
            return event
        }
    }
}
