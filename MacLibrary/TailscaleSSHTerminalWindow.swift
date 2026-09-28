import AppKit
import ApplicationLibrary
import Library
import SwiftUI

struct TailscaleSSHTerminalWindow: View {
    let session: TailscaleSSHPresentedSession?

    @Environment(\.openWindow) private var openWindow
    @State private var hostWindow: NSWindow?
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if let session {
                TerminalWrapperView(session)
            } else {
                Color.clear
            }
        }
        .background(WindowAccessor(callback: { window in
            window?.isRestorable = false
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
                peerDisplayName: session.peerDisplayName,
                peerAddress: session.peerAddress,
                username: session.username,
                terminalType: session.terminalType,
                hostKeys: session.hostKeys,
                forwardAgent: session.forwardAgent
            ))
            return nil
        case "q", "w":
            host.close()
            return nil
        default:
            return event
        }
    }
}
