import AppKit
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
}

struct TerminalCommands: Commands {
    @FocusedValue(\.newTerminalWindowAction) var newWindowAction
    @FocusedValue(\.openTerminalWindowAction) var openTerminalWindowAction
    @FocusedValue(\.currentTerminalSession) var currentSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if let newWindowAction {
                let currentSession = currentSession
                let otherQCPeers = TailscaleSSHLaunchService.shared.quickConnectPeers.filter { peer in
                    guard let current = currentSession else { return true }
                    return !(peer.endpointTag == current.endpointTag && peer.peerAddress == current.peerAddress)
                }

                if otherQCPeers.isEmpty {
                    Button("New Window") {
                        newWindowAction()
                    }
                    .keyboardShortcut("n", modifiers: .command)
                } else {
                    Menu("New Window") {
                        Button(currentSession?.peerHostName ?? String(localized: "New Window")) {
                            newWindowAction()
                        }
                        .keyboardShortcut("n", modifiers: .command)

                        Divider()

                        ForEach(otherQCPeers) { peer in
                            Button(peer.hostName) {
                                guard let openAction = openTerminalWindowAction else { return }
                                Task { @MainActor in
                                    let session = await peer.createSession()
                                    openAction(session)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TailscaleSSHTerminalWindow: View {
    let session: TailscaleSSHPresentedSession?

    @Environment(\.openWindow) private var openWindow
    @State private var hostWindow: NSWindow?
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if let session, let maker = TailscaleSSHLaunchService.shared.terminalViewMaker {
                maker(session)
                    .focusedSceneValue(\.newTerminalWindowAction) { [openWindow] in
                        openWindow(value: TailscaleSSHPresentedSession(
                            endpointTag: session.endpointTag,
                            peerHostName: session.peerHostName,
                            peerAddress: session.peerAddress,
                            username: session.username,
                            terminalType: session.terminalType,
                            hostKeys: session.hostKeys
                        ))
                    }
                    .focusedSceneValue(\.openTerminalWindowAction) { [openWindow] newSession in
                        openWindow(value: newSession)
                    }
                    .focusedSceneValue(\.currentTerminalSession, session)
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
        case "q":
            host.close()
            return nil
        default:
            return event
        }
    }
}
