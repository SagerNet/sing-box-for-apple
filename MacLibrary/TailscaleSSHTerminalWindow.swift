import AppKit
import Library
import SwiftUI

struct TailscaleSSHTerminalWindow: View {
    let session: TailscaleSSHPresentedSession?

    @Environment(\.openWindow) private var openWindow
    @State private var hostWindow: NSWindow?
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if let session, let maker = TailscaleSSHLaunchService.shared.terminalViewMaker {
                maker(session)
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
        case "n":
            guard let session else { return nil }
            openWindow(value: TailscaleSSHPresentedSession(
                endpointTag: session.endpointTag,
                peerHostName: session.peerHostName,
                peerAddress: session.peerAddress,
                username: session.username,
                terminalType: session.terminalType,
                hostKeys: session.hostKeys
            ))
            return nil
        default:
            return event
        }
    }
}
