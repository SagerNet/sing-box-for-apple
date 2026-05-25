import AppKit
import Library
import SwiftUI

private struct NewTerminalWindowActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newTerminalWindowAction: (() -> Void)? {
        get { self[NewTerminalWindowActionKey.self] }
        set { self[NewTerminalWindowActionKey.self] = newValue }
    }
}

struct TerminalCommands: Commands {
    @FocusedValue(\.newTerminalWindowAction) var newWindowAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if let newWindowAction {
                Button("New Window") {
                    newWindowAction()
                }
                .keyboardShortcut("n", modifiers: .command)
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
                    .focusedSceneValue(\.newTerminalWindowAction, { [openWindow] in
                        openWindow(value: TailscaleSSHPresentedSession(
                            endpointTag: session.endpointTag,
                            peerHostName: session.peerHostName,
                            peerAddress: session.peerAddress,
                            username: session.username,
                            terminalType: session.terminalType,
                            hostKeys: session.hostKeys
                        ))
                    })
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
