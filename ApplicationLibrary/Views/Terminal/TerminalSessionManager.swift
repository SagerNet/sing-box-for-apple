#if canImport(GhosttyTerminal) && os(iOS)
    import Combine
    import Foundation
    import Library
    import SwiftUI

    @MainActor
    final class TerminalSessionManager: ObservableObject {
        struct ManagedSession: Identifiable {
            let id: UUID
            let presentedSession: TailscaleSSHPresentedSession
            let viewModel: TerminalWrapperViewModel
        }

        @Published private(set) var sessions: [ManagedSession] = []
        @Published var activeSessionID: UUID?
        var onDismissAll: (() -> Void)?

        private var phaseCancellables: [UUID: AnyCancellable] = [:]
        private var viewModelCancellables: [UUID: AnyCancellable] = [:]

        var activeSession: ManagedSession? {
            sessions.first { $0.id == activeSessionID }
        }

        var activeDisplayTitle: String {
            guard let active = activeSession else { return "" }
            return TerminalSessionContentView.displayTitle(
                phase: active.viewModel.phase,
                extrasTitle: active.viewModel.extras.title,
                peerHostName: active.presentedSession.peerHostName
            )
        }

        func displayName(for session: ManagedSession) -> String {
            TerminalSessionContentView.displayTitle(
                phase: session.viewModel.phase,
                extrasTitle: session.viewModel.extras.title,
                peerHostName: session.presentedSession.peerHostName
            )
        }

        func addSession(from presented: TailscaleSSHPresentedSession) {
            let vm = TerminalWrapperViewModel()
            let managed = ManagedSession(
                id: presented.id,
                presentedSession: presented,
                viewModel: vm
            )
            sessions.append(managed)
            activeSessionID = presented.id

            viewModelCancellables[presented.id] = vm.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }

            phaseCancellables[presented.id] = vm.$phase
                .dropFirst()
                .sink { [weak self] phase in
                    if case .finished = phase {
                        let sessionID = presented.id
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                            self?.closeSession(id: sessionID)
                        }
                    }
                }

            vm.start(presented)
        }

        func closeSession(id: UUID) {
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
            let session = sessions[index]
            session.viewModel.disconnect()
            phaseCancellables.removeValue(forKey: id)
            viewModelCancellables.removeValue(forKey: id)
            sessions.remove(at: index)

            if activeSessionID == id {
                activeSessionID = sessions.last?.id
            }

            if sessions.isEmpty {
                onDismissAll?()
            }
        }

        func disconnectAll() {
            for session in sessions {
                session.viewModel.disconnect()
            }
            phaseCancellables.removeAll()
            viewModelCancellables.removeAll()
            sessions.removeAll()
        }

        func switchTo(id: UUID) {
            guard sessions.contains(where: { $0.id == id }) else { return }
            activeSessionID = id
        }

        func createDuplicateSession() {
            guard let active = activeSession else { return }
            let src = active.presentedSession
            let newSession = TailscaleSSHPresentedSession(
                endpointTag: src.endpointTag,
                peerHostName: src.peerHostName,
                peerAddress: src.peerAddress,
                username: src.username,
                terminalType: src.terminalType,
                hostKeys: src.hostKeys,
                forwardAgent: src.forwardAgent
            )
            addSession(from: newSession)
        }

        func addSessionFromPeer(_ peer: TailscaleSSHPeerEntry) {
            Task {
                let session = await peer.createSession()
                addSession(from: session)
            }
        }
    }
#endif
